require 'net/http'

module Helpers
  module SmartStack
    include MiniTest::Chef::Assertions
    include MiniTest::Chef::Context
    include MiniTest::Chef::Resources

    # supports the shell_out function
    require 'chef/mixin/shell_out'
    include Chef::Mixin::ShellOut

    # for querying zookeeper
    def zk_cli(command)
      script = File.join(
        node.smartstack.zk_home,
        "zookeeper-#{node.smartstack.zk_version}",
        'bin/zkCli.sh')
      shell_out("#{script} #{command}")
    end

    def http_take_down(service, max_wait = 10, sleep_time = 0.2)
      port = node.smartstack[service].port
      shell_out("sv down #{service}")

      success = false
      start = Time.now()
      while (Time.now() - max_wait) < start
        begin
          response = Net::HTTP.get_response('localhost', '/health', port)
        rescue Errno::ECONNREFUSED
          success = true
          break
        rescue StandardError
          # other errors are ignored
        else
          sleep sleep_time
        end
      end

      raise StandardError, "service #{service} never went down" unless success
    end

    def http_bring_up(service, max_wait = 10, sleep_time = 0.2)
      port = node.smartstack[service].port
      shell_out("sv up #{service}")

      success = false
      start = Time.now()
      while (Time.now() - max_wait) < start
        begin
          response = Net::HTTP.get_response('localhost', '/health', port)
        rescue
          # nothing
        end

        if response.kind_of? Net::HTTPOK
          success = true
          break
        end

        sleep sleep_time
      end

      raise StandardError, "service #{service} never came up" unless success
    end

    # this is a very naive haproxy config parser, but it's good enough
    # for the testing we want to do
    def parsed_haproxy_config
      path = node.synapse.config.haproxy.config_file_path
      config = {
        'global' => [],
        'defaults' => [],

        'frontend' => {},
        'backend' => {},
        'listen' => {},
      }

      # state machine
      section = nil
      name = nil
      IO.readlines(path).each do |line|
        line.strip!
        next if line.start_with?('#') || line == ''

        # we match the beginning of a section, to enter that section
        first, second, rest = line.split(nil, 3)
        if config.keys.include?(first)
          section = first
          name = second
          if name
            config[section][name] ||= {'config' => []}
          end

          if %w{listen frontend}.include? section
            config[section][name]['address'] = rest
          end

        # otherwise, we should already be in a section
        else
          if %w{global defaults}.include? section
            config[section] << line
          else
            config[section][name]['config'] << line
          end
        end
      end

      return config
    end
  end
end
