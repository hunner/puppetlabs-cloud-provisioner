require 'rubygems'
require 'fog'

Puppet::String.define :node, '0.0.1' do
  action :bootstrap do
    option '--image=', '-i='
    option '--keypair=', '-k='
    option '--group=', '-g=', '--security-group='
    option '--login=', '-l=', '--username='
    option '--keyfile='
    option '--tarball=', '--puppet='
    option '--answers='
    invoke do |name, options|
      options[:_destroy_server_at_exit] = :bootstrap
      server = self.create(nil, options)
      self.init(nil, server, options)
      options.delete(:_destroy_server_at_exit)
    end
  end

  action :init do
    option '--login=', '-l=', '--username='
    option '--keyfile=', '-k='
    option '--tarball=', '--puppet='
    option '--answers='
    invoke do |name, server, options|
      login   = options[:login]
      keyfile = options[:keyfile]

      opts = {}
      opts[:key_data] = [File.read(keyfile)] if keyfile

      ssh = Fog::SSH.new(server, login, opts)
      scp = Fog::SCP.new(server, login, opts)

      print "Waiting for SSH response ..."
      retries = 0
      begin
        # TODO: Certain cases cause this to hang?
        ssh.run(['hostname'])
      rescue Net::SSH::AuthenticationFailed
        puts " Failed"
        raise "Check your authentication credentials and try again."
      rescue => e
        sleep 5
        retries += 1
        print '.'
        puts " Failed"
        raise "SSH not responding; aborting." if retries > 60
        retry
      end
      puts " Done"

      print "Uploading Puppet ..."
      scp.upload(options[:tarball], '/tmp/puppet.tar.gz')
      puts " Done"

      print "Uploading Puppet Answer File ..."
      scp.upload(options[:answers], '/tmp/puppet.answers')
      puts " Done"

      print "Installing Puppet ..."
      steps = [
        'tar -xvzf /tmp/puppet.tar.gz -C /tmp',
        '/tmp/puppet-enterprise-1.0-all/puppet-enterprise-installer -a /tmp/puppet.answers'
      ]
      ssh.run(steps.map { |c| login == 'root' ? cmd : "sudo #{c}" })
      puts " Done"
    end
  end
end