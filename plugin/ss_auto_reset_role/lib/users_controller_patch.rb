# encoding: utf-8

module UsersControllerPatch
  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      unloadable
      alias_method_chain :update, :autoresetrole
    end
  end

  module InstanceMethods
    def update_with_autoresetrole
      ### add: ロール自動アサイン機能 #############################
      #
      # update時のフック箇所
      #
      logger.debug("=================== UsersController: update_with_autoresetrole")
      logger.debug(params.to_yaml)
      logger.debug(edit_user_path(@user))
      is_changed_part = false  # 所属プロジェクト変更フラグ

      # グループタブページの更新時は処理スキップ
      if params[:user][:group_ids].blank?
        ### UserCustomField: 所属プロジェクトのIDを取得
        logger.debug("----- UserCustomField に`所属プロジェクト`が設定されているか？")
        part_name ||= l(:label_part_parent_project) || "所属プロジェクト"
        part_id ||= is_exist_and_get_id(UserCustomField, part_name)
        logger.debug("*** UserCustomField is `#{part_name}`, ID=`#{part_id}`")
        # 所属プロジェクトが存在しない場合は処理スキップ
        if part_id.present?
          ### 所属プロジェクトの現在値と画面選択値を比較, フラグ更新
          current_part = @user.custom_field_values.find{|c| c.custom_field.id == part_id}
          new_part = params[:user][:custom_field_values][part_id.to_s]
          is_changed_part = current_part.to_s != new_part.to_s
          logger.debug("*** UCF-part is chanded: #{is_changed_part}, `#{current_part}` => `#{new_part}`")
        end
      end
      #######################################################################

      @user.admin = params[:user][:admin] if params[:user][:admin]
      @user.login = params[:user][:login] if params[:user][:login]
      if params[:user][:password].present? && (@user.auth_source_id.nil? || params[:user][:auth_source_id].blank?)
        @user.password, @user.password_confirmation = params[:user][:password], params[:user][:password_confirmation]
      end

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

        ### add: ロール自動アサイン機能 #####################################
        # 所属プロジェクト変更フラグがtrueならreset_roleに飛ぶ
        # reset_roleの結果がfalseなら後続スキップ
        return unless reset_role_user(new_part) if is_changed_part
        #####################################################################

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

    private

    ### for update_with_autoresetrole
    # 親プロジェクトのロールリセット、ロール付与で使用
    # 指定したproject_idにアサインされているロールのm_idとrole_id(s)を返す
    # 未アサインならm_id=nil, role_ids=[]を返す
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

    ### for update_with_autoresetrole
    # 所属プロジェクト、一般ユーザの定義有無チェックで使用
    # 指定したclsにnameが存在する場合、そのidを返す
    # 無い場合は500エラーを表示、メッセージは:error_is_not_exist(name)
    def is_exist_and_get_id(cls, name)
      ins = cls.find_by_name(name)
      logger.debug("*** is_exist?: `#{name}` in #{cls}")
      if ins.nil?
        logger.error("ERROR: cannot found `#{name}` in #{cls}.")
        return nil
      end
      ins[:id]
    end

    ### for update_with_autoresetrole
    #
    # ロール自動アサイン機能本体
    #
    def reset_role_user(new_part=nil)
      logger.debug("################ reset_role_user #################")
      logger.debug("*** params=#{params.inspect}")
      logger.debug("*** @user=#{@user.inspect}")
      ippan_role_name ||= l(:label_ippan_role_name) || "一般ユーザ"
      thd_pjt_name ||= l(:label_thd_pjt_name) || "THD"

      ### Role: 一般ユーザのIDを取得, 無かったら500エラーでreturn
      logger.debug("----- `#{ippan_role_name}`が存在するか？")
      ippan_role_id ||= is_exist_and_get_id(Role, ippan_role_name)
      logger.debug("*** reset-Role is `#{ippan_role_name}`, ID=`#{ippan_role_id}`")
      (render_error l(:error_is_not_exist, ippan_role_name); return false) unless ippan_role_id.present?

      ### 親プロジェクトから一般ユーザを削除
      logger.debug("----- 親プロジェクトにアサインされたロール一覧を取得")
      parent_pjts = Project.where(parent_id: nil)
      logger.debug("*** parent_pjts: #{parent_pjts.inspect}")
      parent_pjts.each do |pjt|
        m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
        logger.debug("*** get roles in #{pjt[:name]}(ID: #{pjt[:id]}) => #{[m_id, role_ids]}")

        ### 親プロジェクトにアサイン＆一般ユーザが存在の場合
        if m_id.present? && role_ids.delete(ippan_role_id)
          logger.debug("----- 一般ユーザを削除: #{pjt[:name]}")
          logger.debug("*** changed role_ids: #{role_ids}")
          membership = Member.edit_membership(m_id, {"role_ids" => role_ids}, @user)
          membership.save
        end
      end

      ### 所属なし選択の場合はここで終了
      return true unless new_part.present?

      ### 選択した所属に従って、親プロジェクトに一般ユーザを付与
      parent_pjts.each do |pjt|
        ### 親プロジェクト毎に、以下のルールでロール付与
        # 1) I'm THD. all PJTs OK.
        # 2) We're allowed THD-PJT.
        # 3) I'm allowed only My-PJT.
        if new_part == thd_pjt_name || pjt[:name] == thd_pjt_name || pjt[:name] == new_part
          logger.debug("----- 一般ユーザを付与: #{pjt[:name]}")
          m_id, role_ids = get_user_roles_by_projectid(pjt[:id])
          role_ids.push(ippan_role_id)
          logger.debug("*** update Role: M_ID: #{m_id}, Roles: #{role_ids}")
          membership = Member.edit_membership(m_id, {"project_id"=>pjt[:id], "role_ids" => role_ids}, @user)
          membership.save
        end
      end
      logger.debug("###########################################")
    end
  end
end

UsersController.send(:include, UsersControllerPatch)
