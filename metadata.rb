name             'smartstack'
maintainer       'Igor Serebryany'
maintainer_email 'igor.serebryany@airbnb.com'
license          'MIT'
version          '0.7.0'

description      'The cookbook for configuring Airbnb SmartStack'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))

depends 'sudo'

recipe           'smartstack::nerve', 'Installs and configures nerve, the service registry component'
recipe           'smartstack::synapse', 'Installs and confgures a synapse, the service discovery component'
