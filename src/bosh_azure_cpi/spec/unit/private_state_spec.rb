# frozen_string_literal: true

require 'spec_helper'

describe 'CPI private state files' do
  let(:helper) { Object.new.extend(Bosh::AzureCloud::Helpers) }

  before do
    @directory = Dir.mktmpdir('azure-private-state-')
    directory = @directory
    @state = File.join(directory, 'state')
    @events = File.join(@state, 'events')
    @timestamp = File.join(@state, 'events_last_update')
    @telemetry_log = File.join(@state, 'telemetry.log')
    stub_const('Bosh::AzureCloud::Helpers::CPI_LOCK_DIR', @state)
    stub_const('Bosh::AzureCloud::Helpers::CPI_EVENTS_DIR', @events)
    stub_const('Bosh::AzureCloud::Helpers::CPI_EVENT_HANDLER_LAST_POST_TIMESTAMP', @timestamp)
    stub_const('Bosh::AzureCloud::Helpers::CPI_TELEMETRY_LOG_FILE', @telemetry_log)
  end

  after do
    FileUtils.remove_entry(@directory) if @directory
  end

  it 'preserves ordinary lock names while keeping directory and files private' do
    Dir.mkdir(@state, 0o755)
    expect(helper.flock('resource-name.version(東京)', File::LOCK_EX) { :locked }).to eq(:locked)
    expect(File.stat(@state).mode & 0o777).to eq(0o700)
    expect(File.stat(File.join(@state, 'resource-name.version(東京)')).mode & 0o777).to eq(0o600)
  end

  it 'rejects path components before creating or locking an outside file' do
    Dir.mkdir(@state, 0o700)
    ['../escaped', '/absolute', 'nested/name', 'back\\slash', "null\0name", '.', '..', ''].each do |name|
      expect { helper.flock(name, File::LOCK_EX) { raise 'must not run' } }.to raise_error(Bosh::Clouds::CloudError, /Invalid CPI lock name/)
    end
    expect(File.exist?(File.join(@directory, 'escaped'))).to be(false)
  end

  it 'rejects a pre-created state-directory symlink without touching its target' do
    target = File.join(@directory, 'target')
    Dir.mkdir(target, 0o755)
    File.symlink(target, @state)
    expect { helper.flock('safe', File::LOCK_EX) { raise 'must not run' } }.to raise_error(Bosh::Clouds::CloudError, /Unsafe CPI state directory/)
    expect(Dir.children(target)).to be_empty
    expect(File.stat(target).mode & 0o777).to eq(0o755)
  end

  it 'rejects state directories writable by another user or group' do
    Dir.mkdir(@state)
    File.chmod(0o777, @state)
    expect { helper.flock('safe', File::LOCK_EX) { raise 'must not run' } }.to raise_error(Bosh::Clouds::CloudError, /Unsafe CPI state directory/)
    expect(File.stat(@state).mode & 0o777).to eq(0o777)
  end

  it 'rejects state directories owned by another account' do
    Dir.mkdir(@state, 0o700)
    allow(File).to receive(:lstat).and_call_original
    allow(File).to receive(:lstat).with(@state).and_return(instance_double(File::Stat, directory?: true, uid: Process.euid + 1, mode: 0o700))
    expect { helper.flock('safe', File::LOCK_EX) { raise 'must not run' } }.to raise_error(Bosh::Clouds::CloudError, /Unsafe CPI state directory/)
  end

  it 'does not follow a lock symlink or modify a hard-linked target' do
    Dir.mkdir(@state, 0o700)
    target = File.join(@directory, 'target')
    File.write(target, 'fixture-sensitive-content')
    File.chmod(0o640, target)
    File.symlink(target, File.join(@state, 'symlink'))
    File.link(target, File.join(@state, 'hardlink'))
    expect { helper.flock('symlink', File::LOCK_EX) { raise 'must not run' } }.to raise_error(Errno::ELOOP)
    expect { helper.flock('hardlink', File::LOCK_EX) { raise 'must not run' } }.to raise_error(Bosh::Clouds::CloudError, /Unsafe CPI state file/)
    expect(File.read(target)).to eq('fixture-sensitive-content')
    expect(File.stat(target).mode & 0o777).to eq(0o640)
  end

  it 'does not follow a telemetry timestamp symlink during a write' do
    Dir.mkdir(@state, 0o700)
    target = File.join(@directory, 'target')
    File.write(target, 'fixture-sensitive-content')
    File.symlink(target, @timestamp)
    handler = Bosh::AzureCloud::TelemetryEventHandler.new(Logger.new(StringIO.new))
    expect { handler.send(:update_last_post_timestamp, Time.now) }.to raise_error(Errno::ELOOP)
    expect(File.read(target)).to eq('fixture-sensitive-content')
  end

  it 'does not follow a telemetry log symlink during initialization' do
    Dir.mkdir(@state, 0o700)
    target = File.join(@directory, 'target')
    File.write(target, 'fixture-sensitive-content')
    File.symlink(target, @telemetry_log)
    expect { Bosh::AzureCloud::TelemetryManager.new(mock_azure_config) }.to raise_error(Errno::ELOOP)
    expect(File.read(target)).to eq('fixture-sensitive-content')
  end

  it 'rejects event-file symlinks before reading their targets' do
    Dir.mkdir(@state, 0o700)
    Dir.mkdir(@events, 0o700)
    target = File.join(@directory, 'target')
    File.write(target, '{"secret":"fixture-sensitive-content"}')
    File.symlink(target, File.join(@events, 'event.tld'))
    logs = StringIO.new
    handler = Bosh::AzureCloud::TelemetryEventHandler.new(Logger.new(logs))
    expect { handler.send(:collect_events) }.to raise_error(Errno::ELOOP)
    expect(logs.string).not_to include('fixture-sensitive-content')
    expect(File.read(target)).to eq('{"secret":"fixture-sensitive-content"}')
  end

  it 'publishes complete private events atomically and leaves no pending file' do
    manager = Bosh::AzureCloud::TelemetryManager.new(mock_azure_config)
    allow(manager).to receive(:fork)
    manager.send(:_report_event, double('event', to_json: '{"fixture":"event"}'))
    files = Dir[File.join(@events, '*.tld')]
    expect(files.size).to eq(1)
    expect(File.read(files.first)).to eq('{"fixture":"event"}')
    expect(File.stat(files.first).mode & 0o777).to eq(0o600)
    expect(Dir[File.join(@events, '*.pending')]).to be_empty
    expect(File.stat(@telemetry_log).mode & 0o777).to eq(0o600)
    manager.instance_variable_get(:@logger).close
  end
end
