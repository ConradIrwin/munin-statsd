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

if __FILE__==$0
  opts[:munin_hosts].each do |hostname|
    node = Munin::Node.new(hostname, opts[:munin_port])
    statsd = Statsd.new(opts[:statsd_host], opts[:statsd_port])
    statsd.namespace = opts[:schema_base] || hostname.split(".").first

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