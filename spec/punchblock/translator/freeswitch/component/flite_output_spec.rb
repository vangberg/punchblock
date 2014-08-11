# encoding: utf-8

require 'spec_helper'

module Punchblock
  module Translator
    class Freeswitch
      module Component
        describe FliteOutput do
          include HasMockCallbackConnection

          let(:translator)  { Punchblock::Translator::Freeswitch.new connection }
          let(:mock_call)   { Punchblock::Translator::Freeswitch::Call.new 'foo', translator }

          let :original_command do
            Punchblock::Component::Output.new command_options
          end

          let :ssml_doc do
            RubySpeech::SSML.draw do
              say_as(:interpret_as => :cardinal) { 'FOO' }
            end
          end

          let :command_options do
            { :render_document => {:value => ssml_doc} }
          end

          def execute
            subject.execute
          end

          subject { described_class.new original_command, mock_call }

          describe '#execute' do
            before { original_command.request! }
            def expect_playback(voice = :kal, doc = "FOO")
              expect(subject.wrapped_object).to receive(:application).once.with :speak, "flite|#{voice}|#{doc}"
            end

            let(:command_opts) { {} }

            let :command_options do
              { :render_document => {:value => ssml_doc} }.merge(command_opts)
            end

            let :original_command do
              Punchblock::Component::Output.new command_options
            end

            describe 'document' do
              context 'unset' do
                let(:ssml_doc) { nil }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'An SSML document is required.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end

              context 'with an SSML node' do
                it 'should speak the document using the speak application' do
                  expect_playback
                  execute
                end

                it 'should send a complete event when the speak finishes' do
                  expect_playback
                  execute
                  subject.handle_es_event RubyFS::Event.new(nil, :event_name => "CHANNEL_EXECUTE_COMPLETE")
                  expect(original_command.complete_event(0.1).reason).to be_a Punchblock::Component::Output::Complete::Finish
                end
              end

              context 'with multiple documents' do
                let(:command_opts) { { :render_documents => [{:value => ssml_doc}, {:value => ssml_doc}] } }

                it "should render all audio files from all documents" do
                  expect_playback :kal, "FOOFOO"
                  subject.execute
                end
              end
            end

            describe 'start-offset' do
              context 'unset' do
                let(:command_opts) { { :start_offset => nil } }
                it 'should not pass any options to Playback' do
                  expect_playback
                  execute
                end
              end

              context 'set' do
                let(:command_opts) { { :start_offset => 10 } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'A start_offset value is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end

            describe 'start-paused' do
              context 'false' do
                let(:command_opts) { { :start_paused => false } }
                it 'should not pass any options to Playback' do
                  expect_playback
                  execute
                end
              end

              context 'true' do
                let(:command_opts) { { :start_paused => true } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'A start_paused value is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end

            describe 'repeat-interval' do
              context 'unset' do
                let(:command_opts) { { :repeat_interval => nil } }
                it 'should not pass any options to Playback' do
                  expect_playback
                  execute
                end
              end

              context 'set' do
                let(:command_opts) { { :repeat_interval => 10 } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'A repeat_interval value is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end

            describe 'repeat-times' do
              context 'unset' do
                let(:command_opts) { { :repeat_times => nil } }
                it 'should not pass any options to Playback' do
                  expect_playback
                  execute
                end
              end

              context 'set' do
                let(:command_opts) { { :repeat_times => 2 } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'A repeat_times value is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end

            describe 'max-time' do
              context 'unset' do
                let(:command_opts) { { :max_time => nil } }
                it 'should not pass any options to Playback' do
                  expect_playback
                  execute
                end
              end

              context 'set' do
                let(:command_opts) { { :max_time => 30 } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'A max_time value is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end

            describe 'voice' do
              context 'unset' do
                let(:command_opts) { { :voice => nil } }
                it 'should use the default voice' do
                  expect_playback
                  execute
                end
              end

              context 'set' do
                let(:command_opts) { { :voice => 'alison' } }
                it "should execute speak with the specified voice" do
                  expect_playback 'alison'
                  execute
                end
              end
            end

            describe 'interrupt_on' do
              context "set to nil" do
                let(:command_opts) { { :interrupt_on => nil } }
                it "should not pass any digits to Playback" do
                  expect_playback
                  execute
                end
              end

              context "set to :any" do
                let(:command_opts) { { :interrupt_on => :any } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'An interrupt-on value of any is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end

              context "set to :dtmf" do
                let(:command_opts) { { :interrupt_on => :dtmf } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'An interrupt-on value of dtmf is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end

              context "set to :voice" do
                let(:command_opts) { { :interrupt_on => :voice } }
                it "should return an error and not execute any actions" do
                  execute
                  error = ProtocolError.new.setup 'option error', 'An interrupt-on value of voice is unsupported.'
                  expect(original_command.response(0.1)).to eq(error)
                end
              end
            end
          end

          describe "#execute_command" do
            context "with a command it does not understand" do
              let(:command) { Punchblock::Component::Output::Pause.new }

              before { command.request! }

              it "returns a ProtocolError response" do
                subject.execute_command command
                expect(command.response(0.1)).to be_a ProtocolError
              end
            end

            context "with a Stop command" do
              let(:command) { Punchblock::Component::Stop.new }
              let(:reason) { original_command.complete_event(5).reason }

              before do
                command.request!
                original_command.request!
                original_command.execute!
              end

              it "sets the command response to true" do
                expect(subject.wrapped_object).to receive(:application)
                subject.execute_command command
                expect(command.response(0.1)).to eq(true)
              end

              it "sends the correct complete event" do
                expect(subject.wrapped_object).to receive(:application)
                expect(original_command).not_to be_complete
                subject.execute_command command
                expect(reason).to be_a Punchblock::Event::Complete::Stop
                expect(original_command).to be_complete
              end

              it "breaks the current dialplan application" do
                expect(subject.wrapped_object).to receive(:application).once.with 'break'
                subject.execute_command command
              end
            end
          end
        end

      end
    end
  end
end
