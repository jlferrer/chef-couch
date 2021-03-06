couch_service 'default' do
  action [:create, :start]
end

couch_config 'test_config' do
  action :create
  source 'test_config.erb'
  notifies :restart, 'couch_service[default]', :delayed
end
