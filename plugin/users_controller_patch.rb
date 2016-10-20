# encoding: utf-8

module UsersControllerPatch
  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      unloadable
      alias_method_chain :update, :autoresetrole
      alias_method_chain :edit_membership, :autoresetrole
    end
  end

  module InstanceMethods
    def update_with_autoresetrole
      @user.admin = params[:user][:admin] if params[:user][:admin]
      @user.login = params[:user][:login] if params[:user][:login]
      if params[:user][:password].present? && (@user.auth_source_id.nil? || params[:user][:auth_source_id].blank?)
        @user.password, @user.password_confirmation = params[:user][:password], params[:user][:password_confirmation]
      end

      #-- [Add] --------------------------
      logger.debug("=================== update_with_autoresetrole")
      reset_role
      #-----------------------------------

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

    def edit_membership_with_autoresetrole
      logger.debug("===================edit_membership_with_autoresetrole")
      logger.debug(params[:membership_id])
      logger.debug(params[:membership])
      logger.debug("==================================")
      @membership = Member.edit_membership(params[:membership_id], params[:membership], @user)
      #@membership.save
      respond_to do |format|
        format.html { redirect_to edit_user_path(@user, :tab => 'memberships') }
        format.js
      end
    end

    private

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

    def reset_role
      logger.debug("################ reset_role #################")
      corp_ucf_name ||= "所属プロジェクト"
      thd_pjt_name ||= "THD"
      ippan_role_name ||= "一般ユーザ"

      logger.debug("----- 各種ID取得")
      corp_ucf_id ||= UserCustomField.find_by_name(corp_ucf_name)[:id]
      thd_pjt_id ||= Project.find_by_name(thd_pjt_name)[:id]
      ippan_role_id ||= Role.find_by_name(ippan_role_name)[:id]
      logger.debug("### first: #{corp_ucf_name} => #{corp_ucf_id}")
      logger.debug("### first: #{thd_pjt_name} => #{thd_pjt_id}")
      logger.debug("### first: #{ippan_role_name} => #{ippan_role_id}")

      logger.debug("----- 画面選択した所属プロジェクトが変更されたか？")
      input_ucf_val = params[:user][:custom_field_values][corp_ucf_id.to_s]
      user_ucf_val = @user.custom_field_values.detect{|c| c.custom_field.name == corp_ucf_name}
      logger.debug("*** CF-value: #{user_ucf_val} => #{input_ucf_val}")

      ### 所属未変更の場合はここで終了
      return if user_ucf_val.to_s == input_ucf_val

      ### 親プロジェクトから一般ユーザを削除
      logger.debug("----- 親プロジェクトにアサインされたロール一覧を取得")
      parent_pjts = Project.where(parent_id: nil)
      parent_pjts.each do |pjt|
        m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
        logger.debug("*** get_user_roles_by_projectid(#{pjt[:id]}) => #{[m_id, role_ids]}")

        ### 親プロジェクトにアサイン＆一般ユーザが存在の場合
        if m_id.present? && role_ids.delete(ippan_role_id)
          logger.debug("----- ロール一覧から一般ユーザを削除")
          logger.debug("*** change role_ids => #{role_ids}")
          membership = Member.edit_membership(m_id, {"role_ids" => role_ids}, @user)
          membership.save
        end
      end

      ### 所属なし選択の場合はここで終了
      return unless input_ucf_val.present?

      ### 選択した所属に従って、親プロジェクトに一般ユーザを付与
      parent_pjts.each do |pjt|
        ### I'm THD. all PJTs OK.
        ### We're allowed THD-PJT.
        ### I'm allowed only My-PJT.
        if input_ucf_val == thd_pjt_name || pjt[:name] == thd_pjt_name || pjt[:name] == input_ucf_val
          logger.debug("----- 一般ユーザを付与 #{pjt[:name]}")
          m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
          role_ids.push(ippan_role_id)
          logger.debug("--> M_ID: #{m_id} / Roles: #{role_ids}")
          membership = Member.edit_membership(m_id, {"project_id"=>pjt[:id], "role_ids" => role_ids}, @user)
          membership.save
        end
      end
      logger.debug("###########################################")
    end
  end
end

UsersController.send(:include, UsersControllerPatch)
