# encoding: utf-8
require 'users_controller_patch'
require 'groups_controller_patch'

Redmine::Plugin.register :ss_separation_and_resetrole do
  name 'SS Kanri Separation and autoreset-Role plugin'
  author 'IBS 2016'
  description '個社分離＆ロール自動アサイン機能'
  version '0.0.1'
end
