# -*- coding: utf-8 -*-
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

class UsersController < ApplicationController
  layout 'admin'

  before_filter :require_admin, :except => :show
  before_filter :find_user, :only => [:show, :edit, :update, :destroy, :edit_membership, :destroy_membership]
  accept_api_auth :index, :show, :create, :update, :destroy

  helper :sort
  include SortHelper
  helper :custom_fields
  include CustomFieldsHelper

  def index
    sort_init 'login', 'asc'
    sort_update %w(login firstname lastname mail admin created_on last_login_on)

    case params[:format]
    when 'xml', 'json'
      @offset, @limit = api_offset_and_limit
    else
      @limit = per_page_option
    end

    @status = params[:status] || 1

    scope = User.logged.status(@status)
    scope = scope.like(params[:name]) if params[:name].present?
    scope = scope.in_group(params[:group_id]) if params[:group_id].present?

    @user_count = scope.count
    @user_pages = Paginator.new @user_count, @limit, params['page']
    @offset ||= @user_pages.offset
    @users =  scope.order(sort_clause).limit(@limit).offset(@offset).all

    respond_to do |format|
      format.html {
        @groups = Group.all.sort
        render :layout => !request.xhr?
      }
      format.api
    end
  end

  def show
    # show projects based on current user visibility
    @memberships = @user.memberships.all(:conditions => Project.visible_condition(User.current))

    events = Redmine::Activity::Fetcher.new(User.current, :author => @user).events(nil, nil, :limit => 10)
    @events_by_day = events.group_by(&:event_date)

    unless User.current.admin?
      if !@user.active? || (@user != User.current  && @memberships.empty? && events.empty?)
        render_404
        return
      end
    end

    respond_to do |format|
      format.html { render :layout => 'base' }
      format.api
    end
  end

  def new
    @user = User.new(:language => Setting.default_language, :mail_notification => Setting.default_notification_option)
    @auth_sources = AuthSource.all
  end

  def create
    @user = User.new(:language => Setting.default_language, :mail_notification => Setting.default_notification_option)
    @user.safe_attributes = params[:user]
    @user.admin = params[:user][:admin] || false
    @user.login = params[:user][:login]
    @user.password, @user.password_confirmation = params[:user][:password], params[:user][:password_confirmation] unless @user.auth_source_id

    if @user.save
      @user.pref.attributes = params[:pref]
      @user.pref[:no_self_notified] = (params[:no_self_notified] == '1')
      @user.pref.save
      @user.notified_project_ids = (@user.mail_notification == 'selected' ? params[:notified_project_ids] : [])

      Mailer.account_information(@user, params[:user][:password]).deliver if params[:send_information]

      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_user_successful_create, :id => view_context.link_to(@user.login, user_path(@user)))
          if params[:continue]
            redirect_to new_user_path
          else
            redirect_to edit_user_path(@user)
          end
        }
        format.api  { render :action => 'show', :status => :created, :location => user_url(@user) }
      end
    else
      @auth_sources = AuthSource.all
      # Clear password input
      @user.password = @user.password_confirmation = nil

      respond_to do |format|
        format.html { render :action => 'new' }
        format.api  { render_validation_errors(@user) }
      end
    end
  end

  def edit
    @auth_sources = AuthSource.all
    @membership ||= Member.new
  end

  def update
    @user.admin = params[:user][:admin] if params[:user][:admin]
    @user.login = params[:user][:login] if params[:user][:login]
    if params[:user][:password].present? && (@user.auth_source_id.nil? || params[:user][:auth_source_id].blank?)
      @user.password, @user.password_confirmation = params[:user][:password], params[:user][:password_confirmation]
    end

    logger.debug("===================update0")
    logger.debug(params[:user])
    logger.debug("===================update0-1")
    ### PJT名からIDを取ってくる方法
    pjt_name = "インテリジェンス"
    @project = Project.find_by_name(pjt_name)
    logger.debug(@project.to_yaml)
    pjt_id = @project[:id]
    logger.debug("PJT-ID: #{pjt_id}")
    logger.debug("===================update0-2")
    ### CF名からIDを取ってくる方法
    ucf_name = "所属プロジェクト"
    #@user_custom_field = UserCustomField.find("239")
    @user_custom_field = UserCustomField.find_by_name(ucf_name)
    logger.debug(@user_custom_field.to_yaml)
    cf_id = @user_custom_field[:id]
    logger.debug("CF-ID: #{cf_id}")
    logger.debug("===================update0-3")
    ### 複数UserCFから、所属プロジェクトの値だけ取ってくる
    cfs = params[:user][:custom_field_values]
    cf_value = params[:user][:custom_field_values][cf_id.to_s]
    logger.debug("CFs: #{cfs}")
    logger.debug("CF-ID: #{cf_id}")
    logger.debug("CF-value: #{cf_value}")
    logger.debug("===================update0-4")
    ### 所属プロジェクトのidを取得
    cf_pjt = Project.find(cf_value)
    logger.debug("CF-value: #{cf_value}")
    logger.debug("PJT-ID: #{cf_pjt[:id]}")
    logger.debug("PJT-Name: #{cf_pjt[:name]}")
    logger.debug("===================update0-5")
    ### 一般ユーザのidを取得
    role_name = "一般ユーザ"
    #role = Role.find("一般ユーザ")
    #role = Role.find("14")
    role = Role.find_by_name(role_name)
    logger.debug(role.to_yaml)
    logger.debug("role-id: #{role[:id]}")
    logger.debug("=========================")

    logger.debug("===================update0-params(membership)")
    #params[:membership] = {"project_id"=>"26", "role_ids"=>["14"]}
    params[:membership] = {"project_id"=>cf_pjt[:id].to_s, "role_ids"=>[role[:id].to_s]}
    logger.debug(params.to_yaml)
    logger.debug("===================update0-@membership<-params")
    @membership = Member.edit_membership(params[:membership_id], params[:membership], @user)
    logger.debug(@membership.to_yaml)
    logger.debug("===================update0-membership.save")
    @membership.save
    logger.debug("===================update0-membership.load")
    #@memberships = @user.memberships.all(:conditions => Project.visible_condition(User.current))
    @memberships = @user.memberships
    logger.debug(@memberships.to_yaml)
    logger.debug("=========================")

    @user.safe_attributes = params[:user]
    # Was the account actived ? (do it before User#save clears the change)
    was_activated = (@user.status_change == [User::STATUS_REGISTERED, User::STATUS_ACTIVE])
    # TODO: Similar to My#account
    @user.pref.attributes = params[:pref]
    @user.pref[:no_self_notified] = (params[:no_self_notified] == '1')

    logger.debug("===================update")
    logger.debug(@user.to_yaml)
    logger.debug(@user.pref.to_yaml)
    logger.debug("=========================")

    if @user.save
      @user.pref.save
 
      logger.debug("===================update2")
      logger.debug(@user.pref.to_yaml)
      logger.debug("=========================")

      @user.notified_project_ids = (@user.mail_notification == 'selected' ? params[:notified_project_ids] : [])

      if was_activated
        Mailer.account_activated(@user).deliver
      elsif @user.active? && params[:send_information] && !params[:user][:password].blank? && @user.auth_source_id.nil?
        Mailer.account_information(@user, params[:user][:password]).deliver
      end

      respond_to do |format|
        format.html {
          flash[:notice] = l(:notice_successful_update)
          redirect_to_referer_or edit_user_path(@user)
        }
        format.api  { render_api_ok }
      end
    else
      @auth_sources = AuthSource.all
      @membership ||= Member.new
      # Clear password input
      @user.password = @user.password_confirmation = nil

      respond_to do |format|
        format.html { render :action => :edit }
        format.api  { render_validation_errors(@user) }
      end
    end
  end

  def destroy
    @user.destroy
    respond_to do |format|
      format.html { redirect_back_or_default(users_path) }
      format.api  { render_api_ok }
    end
  end

  def edit_membership
    logger.debug("===================edit_membership")
    logger.debug(params[:membership_id])
    logger.debug(params[:membership])
    logger.debug("==================================")
    @membership = Member.edit_membership(params[:membership_id], params[:membership], @user)
    @membership.save
    respond_to do |format|
      format.html { redirect_to edit_user_path(@user, :tab => 'memberships') }
      format.js
    end
  end

  def destroy_membership
    @membership = Member.find(params[:membership_id])
    if @membership.deletable?
      @membership.destroy
    end
    respond_to do |format|
      format.html { redirect_to edit_user_path(@user, :tab => 'memberships') }
      format.js
    end
  end

  private

  def find_user
    if params[:id] == 'current'
      require_login || return
      @user = User.current
    else
      @user = User.find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
