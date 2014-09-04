# set up common stuff first
include_recipe 'smartstack::default'

# set up haproxy
package 'haproxy' do
  action :upgrade
end

directory node.synapse.haproxy.sock_dir do
  owner 'haproxy'
  group 'haproxy'
end

# allow synapse to write the haproxy config
file node.synapse.config.haproxy.config_file_path do
  owner 'haproxy'
  group node.smartstack.user
  mode  00664
  notifies :restart, 'service[haproxy]', :immediately
end

# allow synapse to restart haproxy
sudo node['smartstack']['user'] do
  user node['smartstack']['user']
  commands ["/sbin/service haproxy reload"]
  nopasswd true
end

# get the synapse code
directory node.synapse.home do
  owner     node.smartstack.user
  group     node.smartstack.user
  recursive true
end

if node.synapse.jarname
  include_recipe 'java'

  url = "#{node.smartstack.jar_source}/synapse/#{node.synapse.jarname}"
  remote_file File.join(node.synapse.home, node.synapse.jarname) do
    source url
    mode   00644
  end
else
  git node.synapse.install_dir do
    user              node.smartstack.user
    group             node.smartstack.user
    repository        node.synapse.repository
    reference         node.synapse.reference
    enable_submodules true
    action     :sync
    notifies   :run, 'execute[synapse_install]', :immediately
    notifies   :restart, 'service[synapse]'
  end

  # do the actual install of synapse and dependencies
  execute "synapse_install" do
    cwd     node.synapse.install_dir
    user    node.smartstack.user
    group   node.smartstack.user
    action  :nothing

    environment ({
      'GEM_HOME' => node.smartstack.gem_home,
      'RBENV_ROOT' => '/usr/local/rbenv'
    })
    command     "/usr/local/rbenv/shims/bundle install --without development"
  end
end

# add the enabled services to the synapse config
# we do this here to avoid wierdness with attribute load order
node.synapse.enabled_services.each do |service_name|
  service = node.smartstack.services[service_name]
  unless service && service.include?('synapse')
    Chef::Log.warn "[synapse] skipping service #{service_name} -- it has no synapse config"
    next
  end

  # build the synapse config hash
  synapse_config = service['synapse'].deep_to_hash

  # set the haproxy port
  synapse_config['haproxy']['port'] = service['local_port']

  # enable proper logging
  if synapse_config['haproxy'].include? 'listen'
    if synapse_config['haproxy']['listen'].include? 'mode http'
      synapse_config['haproxy']['listen'] << 'option httplog'
    elsif synapse_config['haproxy']['listen'].include? 'mode tcp'
      synapse_config['haproxy']['listen'] << 'option tcplog'
    end
  end

  # configure the discovery options
  if synapse_config['discovery']['method'] == "zookeeper"
    unless node['zookeeper'] and node['zookeeper']['smartstack_cluster']
      Chef::Log.warn "[synapse] skipping service #{service_name} -- no zookeeper servers specified"
      next
    end

    synapse_config['discovery']['hosts'] = node['zookeeper']['smartstack_cluster']
    synapse_config['discovery']['path'] = service['zk_path']
  end

  node.default.synapse.config.services[service_name] = synapse_config
end

file node.synapse.config_file do
  owner   node.smartstack.user
  group   node.smartstack.user
  content JSON::pretty_generate(node.synapse.config.deep_to_hash)
  notifies :restart, "service[synapse]"
end

template '/usr/lib/systemd/system/synapse.service' do
  notifies :restart, 'service[synapse]'
end

service 'haproxy' do
  action [:enable, :start]
end

# set up systemd service
service 'synapse' do
  action :enable
  provider Chef::Provider::Service::Systemd
end
