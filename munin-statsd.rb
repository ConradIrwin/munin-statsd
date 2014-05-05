#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'

require 'statsd'
require 'munin-ruby'
require 'trollop'

opts = Trollop::options do
  opt :munin_hosts, "Munin Hosts", type: String, default: "localhost"
  opt :munin_port, "Munin Port", type: Integer, default: 4949
  opt :statsd_host, "Statsd Host", type: String, default: "localhost"
  opt :statsd_port, "Statsd Port", type: Integer, default: 8125
  opt :schema_base, "Schema base (all statsd metrics start with this value -> defaults to machine name)", type: String
  opt :aws, "Get list of instances from AWS"
end

opts[:munin_hosts] = opts[:munin_hosts].split(",")
opts[:munin_hosts].map(&:strip!)

def statsd_method(config, name)
  type = config["metrics"][name]["type"] rescue nil # if there is no configuration or some other problems
  case type
  when "DERIVE", "COUNTER", "ABSOLUTE"
    return :count
  when "GAUGE", nil
    return :gauge
  else
    STDERR.puts "WARNING: unknown munin type #{type} .. using GAUGE instead"
    return :gauge
  end
end

def machines(opts)
  if opts[:aws]
    require 'aws-sdk'
    require 'dotenv'
    Dotenv.load

    AWS.config(
      access_key_id: ENV["BUGSNAG_WEBSITE_AWS_ACCESS_KEY"],
      secret_access_key: ENV["BUGSNAG_WEBSITE_AWS_SECRET_KEY"]
    )
    instances = AWS::EC2::Client.new.describe_instances(filters: [{name: 'instance-state-name', values: ['running']}])
    instances.instance_index.values.map do |instance|
      "#{instance.tag_set.detect{ |x| x[:key] == 'Name' }[:value]}.ec2.bugsnag.com"
    end
  else
    opts[:munin_hosts]
  end
end


if __FILE__==$0
  machines(opts).each do |hostname|
    node = Munin::Node.new(hostname, opts[:munin_port])
    statsd = Statsd.new(opts[:statsd_host], opts[:statsd_port])
    statsd.namespace = opts[:schema_base] || "munin.#{hostname.split(".").first}"

    services = node.list
    configs = node.config services
    all_data = node.fetch services
    services.each do |service|
      config = configs[service]
      data   = all_data[service]

      next if data.nil?

      data.each_pair do |name, value|
        statsd.send(statsd_method(config, name), "#{config["graph"]["category"]}.#{service}.#{name}", value)
      end
    end
  end
end
