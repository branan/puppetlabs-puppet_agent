require 'spec_helper_acceptance'

describe 'puppet_agent class' do

  context 'default parameters' do
    before(:all) { setup_puppet_on default }
    after (:all) { teardown_puppet_on default }

    it 'should work idempotently with no errors' do
      pp = <<-EOS
      class { 'puppet_agent': }
      EOS

      # Run it twice and test for idempotency
      apply_manifest(pp, :catch_failures => true)
      configure_agent_on default
      apply_manifest(pp, :catch_changes  => true)
    end

    describe package('puppet-agent') do
      it { is_expected.to be_installed }
    end

    describe service('puppet') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe service('mcollective') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe file('/etc/puppetlabs/puppet/puppet.conf') do
      it { is_expected.to exist }
      its(:content) {
        is_expected.to match /cfacter[ ]*=[ ]*true/
        is_expected.to_not match /stringify_facts[ ]*=[ ]*false/
        is_expected.to_not match /parser[ ]*=[ ]*future/
      }
    end
  end

  context 'no services enabled on install' do
    before(:all) { setup_puppet_on default }
    after (:all) { teardown_puppet_on default }

    it 'should work idempotently with no errors' do
      pp = <<-EOS
      class { 'puppet_agent': service_names => [] }
      EOS

      # Run it twice and test for idempotency
      apply_manifest(pp, :catch_failures => true)
      configure_agent_on default
      apply_manifest(pp, :catch_changes  => true)
    end

    describe package('puppet-agent') do
      it { is_expected.to be_installed }
    end

    describe service('puppet') do
      it { is_expected.to_not be_running }
    end

    describe service('mcollective') do
      it { is_expected.to_not be_running }
    end
  end

  context 'agent run' do
    before(:all) {
      setup_puppet_on default, :agent => true
      pp = "file { '#{master.puppet['codedir']}/environments/production/manifests/site.pp': ensure => file, content => 'class { \"puppet_agent\": }' }"
      apply_manifest_on(master, pp, :catch_failures => true)
    }
    after (:all) {
      teardown_puppet_on default
      pp = "file { '#{master.puppet['codedir']}/environments/production/manifests/site.pp': ensure => absent }"
      apply_manifest_on(master, pp, :catch_failures => true)
    }

    it 'should work idempotently with no errors' do
      with_puppet_running_on(master, server_opts, master.tmpdir('puppet')) do
        # Run it twice and test for idempotency
        on default, puppet("agent --test --server #{master}"), { :acceptable_exit_codes => [0,2] }
        configure_agent_on default, true
        # We're after idempotency so allow exit code 0 only
        on default, puppet("agent --test --server #{master}"), { :acceptable_exit_codes => [0] }
      end
    end

    describe package('puppet-agent') do
      it { is_expected.to be_installed }
    end

    describe service('puppet') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe service('mcollective') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end
  end

  context 'with mcollective configured' do
    before(:all) {
      setup_puppet_on default, :mcollective => true, :agent => true
      pp = "file { '#{master.puppet['codedir']}/environments/production/manifests/site.pp': ensure => file, content => 'class { \"puppet_agent\": }' }"
      apply_manifest_on(master, pp, :catch_failures => true)
    }
    after (:all) {
      teardown_puppet_on default
      pp = "file { '#{master.puppet['codedir']}/environments/production/manifests/site.pp': ensure => absent }"
      apply_manifest_on(master, pp, :catch_failures => true)
    }

    it 'mco should be running' do
      on default, 'mco ping' do
        hostname = default.hostname.split('.', 2).first
        assert_match(/^#{hostname}[.\w]*\s+time=/, stdout)
      end
    end

    it 'should work idempotently with no errors' do
      with_puppet_running_on(master, server_opts, master.tmpdir('puppet')) do
        # Run it twice and test for idempotency
        on default, puppet("agent --test --server #{master}"), { :acceptable_exit_codes => [0,2] }
        configure_agent_on default, true
        # We're after idempotency so allow exit code 0 only
        on default, puppet("agent --test --server #{master}"), { :acceptable_exit_codes => [0] }
      end
    end

    describe package('puppet-agent') do
      it { is_expected.to be_installed }
    end

    describe service('puppet') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    describe service('mcollective') do
      it { is_expected.to be_enabled }
      it { is_expected.to be_running }
    end

    it 'should have mcollective correctly configured' do
      on default, 'mco ping' do
        hostname = default.hostname.split('.', 2).first
        assert_match(/^#{hostname}[.\w]*\s+time=/, stdout)
      end
    end

    describe file('/etc/puppetlabs/mcollective/server.cfg') do
      it { is_expected.to exist }
      its(:content) {
        is_expected.to include 'libdir = /opt/puppetlabs/mcollective/plugins:/usr/libexec/mcollective/plugins'
        is_expected.to include 'logfile = /var/log/puppetlabs/mcollective.log'
        is_expected.to include 'plugin.yaml = /etc/mcollective/facts.yaml:/etc/puppetlabs/mcollective/facts.yaml'
      }
    end

    describe file('/etc/puppetlabs/mcollective/client.cfg') do
      it { is_expected.to exist }
      its(:content) {
        is_expected.to include 'libdir = /opt/puppetlabs/mcollective/plugins:/usr/libexec/mcollective/plugins'
        is_expected.to include 'logfile = /var/log/puppetlabs/mcollective.log'
        is_expected.to_not match /plugin.yaml[ ]*=/
      }
    end
  end
end
