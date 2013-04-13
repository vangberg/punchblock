# encoding: utf-8

module Punchblock
  module Translator
    class Asterisk
      module Component
        module Asterisk
          class AMIAction < Component
            attr_reader :translator

            def initialize(component_node, translator)
              super component_node, nil
              @translator = translator
            end

            def execute
              send_ref
              handle_response send_action
            end

            private

            def send_action
              @translator.send_ami_action @component_node.name, action_headers
            end

            def handle_response(response)
              case response
              when RubyAMI::Error
                send_complete_event error_reason(response)
              when RubyAMI::Response
                final_event = send_events response
                send_complete_event success_reason(response, final_event)
              end
            end

            def error_reason(response)
              Punchblock::Event::Complete::Error.new :details => response.message
            end

            def success_reason(response, final_event = nil)
              headers = response.headers
              headers.merge! final_event.headers if final_event
              headers.delete 'ActionID'
              Punchblock::Component::Asterisk::AMI::Action::Complete::Success.new :message => headers.delete('Message'), :attributes => headers
            end

            def send_events(response)
              final_event = response.events.pop
              response.events.each do |e|
                send_event pb_event_from_ami_event(e)
              end
              final_event
            end

            def pb_event_from_ami_event(ami_event)
              headers = ami_event.headers
              headers.delete 'ActionID'
              Event::Asterisk::AMI::Event.new :name => ami_event.name, :attributes => headers
            end

            def action_headers
              headers = {}
              @component_node.params_hash.each_pair do |key, value|
                headers[key.to_s.capitalize] = value
              end
              headers
            end
          end
        end
      end
    end
  end
end
