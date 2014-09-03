# set up common smartstack stuff
user node.smartstack.user do
  home    node.smartstack.home
  shell   '/sbin/nologin'
  system  true
end

directory node.smartstack.home do
  owner     node.smartstack.user
  group     node.smartstack.user
  recursive true
end

# we need git to install smartstack
package 'git'

gem_package 'bundler'
