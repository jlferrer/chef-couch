require 'uri'
require 'chef/provider/lwrp_base'
require 'chef/provider/package'

require_relative 'helpers'

class Chef
  class Provider
    class CouchService < Chef::Provider::LWRPBase
      include Couch::Helpers
      use_inline_resources if defined?(use_inline_resources)

      action :create do
        if new_resource.from_source
          install_from_source
        else
          install_from_package
        end

        configure_local_ini

        # Create a file that gets added to the end of the config
        # chain for Couchdb so CouchDB will write to it
        file ::File.join(local_ini_dir(new_resource), 'z_couch_config.ini') do
          action :create_if_missing
        end
      end

      action :delete do
        if new_resource.from_source
          directory new_resource.path_prefix do
            action :delete
          end
        else
          #TODO: Implement remove from package
        end
      end

      def install_from_source
        install_dev_packages

        user 'couchdb' do
          comment 'couchdb admin'
          manage_home false
          system true
          home new_resource.path_prefix
        end

        directory new_resource.path_prefix do
          recursive true
          action :create
          owner 'couchdb'
          group 'couchdb'
        end

        conf_opts = [ "--prefix=#{new_resource.path_prefix}" ]
        # If Erlang is installed tell autoconf where to find the headers
        if rhel_erlang_installed?
          bitness = node['kernel']['machine'] =~ /64/ ? 'lib64' : 'lib'
          conf_opts.push "--with-erlang=/usr/#{bitness}/erlang/usr/include"
        end

        ark new_resource.source_package do
          url ::URI.join(new_resource.source_url, new_resource.source_package).to_s
          action :install_with_make
          checksum new_resource.source_checksum
          version new_resource.source_version
          prefix_root Chef::Config[:file_cache_path]
          autoconf_opts conf_opts
        end
      end

      def configure_local_ini
        template local_ini_file do
          action :create
          owner 'couchdb'
          group 'couchdb'
          mode 0660
          cookbook 'couch'
          variables({
            port: new_resource.port,
            bind_address: new_resource.bind_address
          })
        end
      end

      def rhel_erlang_installed?
        return false unless node['platform_family'] == 'rhel'
        ## Load the yum cache and see if esl-erlang is installed
        yum = Chef::Provider::Package::Yum::YumCache.instance
        return false unless yum.package_available? 'erlang'

        yum.installed_version('erlang').nil? ? false : true
      end

      def install_dev_packages
        # EPEL is needed by the dev packages
        if %w(rhel fedora).include? node['platform_family']
          recipe_eval do
            run_context.include_recipe('yum-epel')
          end
        end

        dev_packages.each do |pkg|
          package pkg do
            action :install
          end
        end
      end
    end
  end
end
