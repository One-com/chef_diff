# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

require 'logger'

RSpec.shared_context 'with a silent logger' do
  let(:logger) { Logger.new(File::NULL) }
end
