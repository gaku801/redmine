# -*- coding: utf-8 -*-
#require 'redmine'
require 'users_controller_patch'

#Rails.configuration.to_prepare do
#  require_dependency 'users_controller'
#  unless UsersController.included_modules.include? UsersControllerPatch
#    UsersController.send(:include, UsersControllerPatch)
#  end
#end

Redmine::Plugin.register :ss_separation_and_resetrole do
  name 'SS Kanri Separation and autoreset-Role plugin'
  author 'IBS 2016'
  description '個社分離＆ロール自動アサイン機能'
  version '0.0.1'
end
