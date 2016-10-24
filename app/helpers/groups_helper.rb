# encoding: utf-8
#
# Redmine - project management software
# Copyright (C) 2006-2013  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

module GroupsHelper
  def group_settings_tabs
    tabs = [{:name => 'general', :partial => 'groups/general', :label => :label_general},
            {:name => 'users', :partial => 'groups/users', :label => :label_user_plural},
            {:name => 'memberships', :partial => 'groups/memberships', :label => :label_project_plural}
            ]
  end

  def render_principals_for_new_group_users(group)
    logger.debug("##### helper/Group/render_principals_for_new_group_users")
    logger.debug("*** group=#{group}")
    logger.debug("*** @group=#{@group}, #{@group.class}")
    logger.debug("*** @group_part=#{@group_part}, #{@group_part.class}")
    #my_part = @group.custom_field_values.detect{|c| c.custom_field.name == l(:label_part_parent_project)}.to_s
    my_part = @group.get_part	# 所属プロジェクト名を取得
    logger.debug("*** my_part=#{my_part}, #{my_part.class}")
    logger.debug("*** params=#{params}")
    logger.debug("*** params.group_part=#{params[:group_part]}")
    # userと同じようにtabを渡してあげればここで評価される
    # /groups/330/edit?tab=users の編集画面右側の検索窓をtabでフィルタする
    # User.tabbedはmodelsで定義したので以下でフィルタできる
    
    scope = User.active.sorted.not_in_group(group).like(params[:q])
    scope = scope.tabbed(my_part)
    principal_count = scope.count
    principal_pages = Redmine::Pagination::Paginator.new principal_count, 100, params['page']
    principals = scope.offset(principal_pages.offset).limit(principal_pages.per_page).all

    s = content_tag('div', principals_check_box_tags('user_ids[]', principals), :id => 'principals')

    links = pagination_links_full(principal_pages, principal_count, :per_page_links => false) {|text, parameters, options|
      link_to text, autocomplete_for_user_group_path(group, parameters.merge(:q => params[:q], :format => 'js')), :remote => true
    }

    s + content_tag('p', links, :class => 'pagination')
  end

  def render_tabs_groups
    tabs = [{:name => '', :partial => 'groups/index', :label => l(:label_project_all)}]
    tabs.concat(@parent_pjts.map{|p| {:name => p[:name], :partial => 'groups/index', :label => p[:name]}})
    render :partial => 'groups/tabs', :locals => {:tabs => tabs}
  end
end
