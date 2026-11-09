# frozen_string_literal: true

# vim: syntax=ruby:expandtab:shiftwidth=2:softtabstop=2:tabstop=2

require 'mixlib/shellout'

# Fakes for the Mixlib::ShellOut commands the repo backends run.
module ShellDouble
  # A command that succeeds and prints stdout_text. run_command returns the
  # command itself, as the real one does, so both `cmd.run_command; cmd.error!`
  # and `new(...).run_command.error!` work, and callers that check
  # exitstatus instead of error! see success too.
  def shell_double(stdout_text)
    cmd = instance_double(Mixlib::ShellOut, error!: nil, exitstatus: 0, stdout: stdout_text)
    allow(cmd).to receive(:run_command).and_return(cmd)
    cmd
  end

  # A command that exits non-zero, so error! raises as the real one would.
  def failing_shell_double
    cmd = instance_double(Mixlib::ShellOut, exitstatus: 1)
    allow(cmd).to receive(:run_command).and_return(cmd)
    allow(cmd).to receive(:error!).and_raise(Mixlib::ShellOut::ShellCommandFailed)
    cmd
  end
end
