# encoding: utf-8

require 'celluloid'
require 'ruby_ami'

module Punchblock
  module Translator
    class Asterisk
      include Celluloid

      extend ActiveSupport::Autoload

      autoload :Call
      autoload :Component

      attr_reader :ami_client, :connection, :media_engine, :calls

      REDIRECT_CONTEXT = 'adhearsion-redirect'
      REDIRECT_EXTENSION = '1'
      REDIRECT_PRIORITY = '1'

      trap_exit :actor_died

      def initialize(ami_client, connection, media_engine = nil)
        pb_logger.debug "Starting up..."
        @ami_client, @connection, @media_engine = ami_client, connection, media_engine
        @calls, @components, @channel_to_call_id = {}, {}, {}
        @fully_booted_count = 0
      end

      def register_call(call)
        @channel_to_call_id[call.channel] = call.id
        @calls[call.id] ||= call
      end

      def deregister_call(call)
        @channel_to_call_id.delete call.channel
        @calls.delete call.id
      end

      def call_with_id(call_id)
        @calls[call_id]
      end

      def call_for_channel(channel)
        call_with_id @channel_to_call_id[channel]
      end

      def register_component(component)
        @components[component.id] ||= component
      end

      def component_with_id(component_id)
        @components[component_id]
      end

      def shutdown
        pb_logger.debug "Shutting down"
        @calls.values.each(&:shutdown!)
        current_actor.terminate!
      end

      def handle_ami_event(event)
        exclusive do
          return unless event.is_a? RubyAMI::Event

          if event.name.downcase == "fullybooted"
            pb_logger.trace "Counting FullyBooted event"
            @fully_booted_count += 1
            if @fully_booted_count >= 2
              handle_pb_event Connection::Connected.new
              @fully_booted_count = 0
              run_at_fully_booted
            end
            return
          end

          handle_varset_ami_event event

          ami_dispatch_to_or_create_call event

          unless ami_event_known_call?(event)
            handle_pb_event Event::Asterisk::AMI::Event.new(:name => event.name, :attributes => event.headers)
          end
        end
      end

      def handle_pb_event(event)
        connection.handle_event event
      end

      def execute_command(command, options = {})
        pb_logger.trace "Executing command #{command.inspect}"
        command.request!

        command.target_call_id ||= options[:call_id]
        command.component_id ||= options[:component_id]

        if command.target_call_id
          execute_call_command command
        elsif command.component_id
          execute_component_command command
        else
          execute_global_command command
        end
      end

      def execute_call_command(command)
        if call = call_with_id(command.target_call_id)
          call.execute_command! command
        else
          command.response = ProtocolError.new.setup :item_not_found, "Could not find a call with ID #{command.target_call_id}", command.target_call_id
        end
      end

      def execute_component_command(command)
        if (component = component_with_id(command.component_id))
          component.execute_command! command
        else
          command.response = ProtocolError.new.setup :item_not_found, "Could not find a component with ID #{command.component_id}", command.target_call_id, command.component_id
        end
      end

      def execute_global_command(command)
        case command
        when Punchblock::Component::Asterisk::AMI::Action
          component = Component::Asterisk::AMIAction.new command, current_actor
          register_component component
          component.execute!
        when Punchblock::Command::Dial
          call = Call.new_link command.to, current_actor
          register_call call
          call.dial! command
        else
          command.response = ProtocolError.new.setup 'command-not-acceptable', "Did not understand command"
        end
      end

      def send_ami_action(name, headers = {}, &block)
        ami_client.send_action name, headers, &block
      end

      def run_at_fully_booted
        send_ami_action('Command', {
          'Command' => "dialplan add extension #{REDIRECT_EXTENSION},#{REDIRECT_PRIORITY},AGI,agi:async into #{REDIRECT_CONTEXT}"
        })
        pb_logger.trace "Added extension extension #{REDIRECT_EXTENSION},#{REDIRECT_PRIORITY},AGI,agi:async into #{REDIRECT_CONTEXT}"
      end

      def check_recording_directory
        pb_logger.warning "Recordings directory #{Component::Record::RECORDING_BASE_PATH} does not exist. Recording might not work." unless File.exists?(Component::Record::RECORDING_BASE_PATH)
      end

      def actor_died(actor, reason)
        return unless reason
        pb_logger.error "A linked actor (#{actor.inspect}) died due to #{reason.inspect}"
        if id = @calls.key(actor)
          pb_logger.info "Dead actor was a call we know about, with ID #{id}. Removing it from the registry..."
          @calls.delete id
          end_event = Punchblock::Event::End.new :target_call_id  => id,
                                                 :reason          => :error
          handle_pb_event end_event
        end
      end

      private

      def handle_varset_ami_event(event)
        return unless event.name == 'VarSet' && event['Variable'] == 'punchblock_call_id' && (call = call_with_id event['Value'])

        pb_logger.trace "Received a VarSet event indicating the full channel for call #{call}"
        @channel_to_call_id.delete call.channel
        pb_logger.trace "Removed call with old channel from channel map: #{@channel_to_call_id}"
        call.channel = event['Channel']
        register_call call
      end

      def ami_dispatch_to_or_create_call(event)
        if ami_event_known_call?(event)
          channels_for_ami_event(event).each do |channel|
            call = call_for_channel channel
            call.process_ami_event! event if call
          end
        elsif event.name.downcase == "asyncagi" && event['SubEvent'] == "Start"
          handle_async_agi_start_event event
        end
      end

      def channels_for_ami_event(event)
        [event['Channel'], event['Channel1'], event['Channel2']].compact
      end

      def ami_event_known_call?(event)
        (event['Channel'] && call_for_channel(event['Channel'])) ||
          (event['Channel1'] && call_for_channel(event['Channel1'])) ||
          (event['Channel2'] && call_for_channel(event['Channel2']))
      end

      def handle_async_agi_start_event(event)
        env = Call.parse_environment event['Env']

        return pb_logger.warn "Ignoring AsyncAGI Start event because it is for an 'h' extension" if env[:agi_extension] == 'h'
        return pb_logger.warn "Ignoring AsyncAGI Start event because it is for an 'Kill' type" if env[:agi_type] == 'Kill'

        pb_logger.trace "Handling AsyncAGI Start event by creating a new call"
        call = Call.new event['Channel'], current_actor, env
        link call
        register_call call
        call.send_offer!
      end
    end
  end
end
