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

    #testmess
    role_auto

    #logger.debug("===================update0-params(membership)")
    #params[:membership] = {"project_id"=>cf_pjt[:id].to_s, "role_ids"=>[role[:id].to_s]}
    #logger.debug(params.to_yaml)
    #logger.debug("===================update0-@membership<-params")
    #@membership = Member.edit_membership(params[:membership_id], params[:membership], @user)
    #logger.debug(@membership.to_yaml)
    #logger.debug("===================update0-membership.save")
    #@membership.save
    #logger.debug("===================update0-membership.load")
    ##@memberships = @user.memberships.all(:conditions => Project.visible_condition(User.current))
    #@memberships = @user.memberships
    #logger.debug(@memberships.to_yaml)
    #logger.debug("=========================")

    @user.safe_attributes = params[:user]
    # Was the account actived ? (do it before User#save clears the change)
    was_activated = (@user.status_change == [User::STATUS_REGISTERED, User::STATUS_ACTIVE])
    # TODO: Similar to My#account
    @user.pref.attributes = params[:pref]
    @user.pref[:no_self_notified] = (params[:no_self_notified] == '1')

    if @user.save
      @user.pref.save
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

  def get_user_roles_by_projectid(project_id)
    u_memberships = @user.memberships.all(:conditions => ["project_id = ?", project_id])
    if u_memberships.present?
      u_m = u_memberships.first
      m_id = u_m[:id]
      role_ids = u_m.roles.map{|r| r[:id]}
      [m_id, role_ids]
    else
      [nil, []]
    end
  end

  def role_auto
    logger.debug("################ role_auto #################")
    ucf_name ||= "所属プロジェクト"
    thd_pjt_name ||= "THD"
    ippan_role_name ||= "一般ユーザ"

    logger.debug("----- 各種ID取得")
    @ucf_id = UserCustomField.find_by_name(ucf_name)[:id]
    @thd_pjt_id = Project.find_by_name(thd_pjt_name)[:id]
    @ippan_role_id = Role.find_by_name(ippan_role_name)[:id]
    @parent_pjts = Project.all(:conditions => ["parent_id IS NULL"])
    logger.debug("### first: #{ucf_name} => #{@ucf_id}")
    logger.debug("### first: #{thd_pjt_name} => #{@thd_pjt_id}")
    logger.debug("### first: #{ippan_role_name} => #{@ippan_role_id}")
    logger.debug("### first: #{@parent_pjts.map{|p| [p[:id], p[:name]]}}")

    logger.debug("----- 画面選択した所属プロジェクトが変更されたか？")
    input_cfv = params[:user][:custom_field_values][@ucf_id.to_s]
    user_cfv = @user.custom_field_values.detect{|c| c.custom_field.name == ucf_name}
    logger.debug("*** CF-value: #{user_cfv} => #{input_cfv}")
    return if user_cfv.to_s == input_cfv 

    logger.debug("----- 親プロジェクトにアサインされたロール一覧を取得")
    @parent_pjts.each do |pjt|
      m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
      logger.debug("*** get_user_roles_by_projectid(#{pjt[:id]}) => #{[m_id, role_ids]}")
        
      ### 親プロジェクトにアサイン＆一般ユーザが存在の場合
      if m_id.present? && role_ids.delete(@ippan_role_id)
        logger.debug("----- ロール一覧から一般ユーザを削除")
        logger.debug("*** change role_ids => #{role_ids}")
        membership = Member.edit_membership(m_id, {"role_ids" => role_ids}, @user)
        membership.save
      end
    end

    ### 所属なしの場合はここで終了
    return unless input_cfv.present?

    @parent_pjts.each do |pjt|
      ### I'm THD. all PJTs OK.
      ### We're allowed THD-PJT.
      ### I'm allowed only My-PJT.
      if input_cfv == thd_pjt_name || pjt[:name] == thd_pjt_name || pjt[:name] == input_cfv

        logger.debug("----- 一般ユーザを付与 #{pjt[:name]}")
        m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
        role_ids.push(@ippan_role_id)
        logger.debug("--> M_ID: #{m_id} / Roles: #{role_ids}")
        membership = Member.edit_membership(m_id, {"project_id"=>pjt[:id], "role_ids" => role_ids}, @user)
        logger.debug(membership.to_yaml)
        membership.save
      end
    end

    logger.debug("###########################################")
  end

  def testmess
    logger.debug("################ testmess #################")
    logger.debug(@user.to_yaml)
    logger.debug(params.to_yaml)

    logger.debug("----- 親ディレクトリのリスト取得")
    @parent_pjts = Project.all(:conditions => ["parent_id IS NULL"])
    @parent_pjts.each do |pjt|
      logger.debug(pjt.inspect)
    end

    logger.debug("----- PJT名からPJT-IDを取ってくる")
    pjt_name = "THD"
    project = Project.find_by_name(pjt_name)
    pjt_id = project[:id]
    logger.debug("#{pjt_name} => #{pjt_id}")

    logger.debug("----- 一般ユーザのRole-idを取得")
    role_name = "一般ユーザ"
    role = Role.find_by_name(role_name)
    role_id = role[:id]
    logger.debug("#{role_name} => #{role_id}")

    logger.debug("----- CF名からCF-IDを取ってくる方法")
    ucf_name = "所属プロジェクト"
    user_custom_field = UserCustomField.find_by_name(ucf_name)
    cf_id = user_custom_field[:id]
    logger.debug("#{ucf_name} => #{cf_id}")

    logger.debug("----- 画面入力した複数UserCFから、所属プロジェクトの値だけ抜く")
    cfs = params[:user][:custom_field_values]
    cf_value = params[:user][:custom_field_values][cf_id.to_s]
    logger.debug("CFs: #{cfs}")
    logger.debug("CF-ID: #{cf_id}")
    logger.debug("CF-value: #{cf_value}")

    logger.debug("----- 画面選択した所属プロジェクトが変更されたか？")
    cv = @user.custom_field_values.detect{|c| c.custom_field.name == ucf_name}
    logger.debug("cv on DB: #{cv}")
    logger.debug(cv.class)
    logger.debug(cf_value.class)
    if cv.to_s != cf_value
      logger.debug("CF-value has changed: #{cv} => #{cf_value}")
    else
      logger.debug("CF-value NotChanged: #{cv} => #{cf_value}")
    end

    logger.debug("----- 画面選択した所属プロジェクトのidを取得")
    cf_pjt = Project.find_by_name(cf_value)
    logger.debug("CF-value: #{cf_value}")
    logger.debug("PJT-ID: #{cf_pjt[:id]} / PJT-Name: #{cf_pjt[:name]}")

    logger.debug("----- 親プロジェクトにアサインされたロール一覧を取得")
    @new_memberships = {}
    @parent_pjts.each do |pjt|
      logger.debug("*** PName: #{pjt[:name]} /  PID: #{pjt[:id]}")
      u_memberships = @user.memberships.all(:conditions => ["project_id = ?", pjt[:id]])
      if u_memberships.present?
        u_m = u_memberships.first
        m_id = u_m[:id]
        roles = u_m.roles
        roleids = roles.map{|r| r[:id]}
        logger.debug("--> #{roles}")
        logger.debug("--> M_ID: #{m_id} / Roles: #{roleids}")
        @new_memberships[pjt[:id]] = {
          :membership_id => m_id,
          :role_ids => roleids
        }
      else
        logger.debug("--> Not asignee")
        @new_memberships[pjt[:id]] = {
          :membership_id => nil,
          :project_id => pjt[:id],
          :role_ids => []
        }
      end
      logger.debug(@new_memberships.to_yaml)
    end

    logger.debug("----- ロール一覧から一般ユーザを削除")
    @new_memberships.each do |k, v|
      logger.debug("#{k} : #{v}")
      if v[:role_ids].delete(role_id)
        logger.debug("*** change role_ids => #{v[:role_ids]}")
        #membership = Member.edit_membership(v[:membership_id], {"role_ids" => v[:role_ids]}, @user)
        #membership.save
      end
    end
    logger.debug(@new_memberships.to_yaml)

    logger.debug("###########################################")
  end
end
