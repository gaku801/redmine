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
    def index_with_divide
      sort_init 'login', 'asc'
      sort_update %w(login firstname lastname mail admin created_on last_login_on)
      ### ORDER BY part
      # sort_update %w(login firstname lastname mail part admin created_on last_login_on)

      case params[:format]
      when 'xml', 'json'
        @offset, @limit = api_offset_and_limit
      else
        @limit = per_page_option
      end

      @status = params[:status] || 1

      ### add: 個社分離に伴う管理画面改善
      ### URI: /users
      logger.debug("############## UserssController.index")
      logger.debug("*** params=#{params}")
      @tab = params[:tab] || ''
      logger.debug("*** @tab=#{@tab}")
      @parent_pjts ||= Project.where(parent_id: nil)
      logger.debug("*** @parent_pjts=#{@parent_pjts.inspect}")

      scope = User.logged.status(@status)
      scope = scope.tabbed(@tab)
      logger.debug("#####################################")
      scope = scope.like(params[:name]) if params[:name].present?
      scope = scope.in_group(params[:group_id]) if params[:group_id].present?

      @user_count = scope.count
      @user_pages = Paginator.new @user_count, @limit, params['page']
      @offset ||= @user_pages.offset
      @users =  scope.order(sort_clause).limit(@limit).offset(@offset).all

      respond_to do |format|
        format.html {
          @groups = Group.tabbed(@tab).all.sort
          ### @groups = Group.all.sort
          render :layout => !request.xhr?
        }
        format.api
      end
      ###################################
    end

    def update_with_autoresetrole
      ### add: ロール自動アサイン機能
      ### URI: /users/<id>/edit
      if params[:user][:group_ids].blank?
        # グループタブページの更新時は処理スキップ
        logger.debug("=================== UsersController: update_with_autoresetrole")
        params[:tab] = 'general'
        logger.debug(params.to_yaml)
        logger.debug("----- cfが変更されたか？")
        user_ucf_vals = @user.custom_field_values.map{|c| c.to_s}   # cfの実データ
        input_ucf_vals = params[:user][:custom_field_values].values # cfの画面選択値
        logger.debug("*** UCF-values: `#{user_ucf_vals}` => `#{input_ucf_vals}`")
        # cfのどれかが更新されたらreset_role_userに飛ぶ
        if user_ucf_vals != input_ucf_vals
          return unless reset_role_user
        end
      end
      ###############################

      # 既存処理(update)
      update_without_autoresetrole
    end
    
    def update_with_autoresetrole_org
      #@user.admin = params[:user][:admin] if params[:user][:admin]
      #@user.login = params[:user][:login] if params[:user][:login]
      #if params[:user][:password].present? && (@user.auth_source_id.nil? || params[:user][:auth_source_id].blank?)
      #  @user.password, @user.password_confirmation = params[:user][:password], params[:user][:password_confirmation]
      #end

      ### add: ロール自動アサイン機能
      if params[:user][:group_ids].blank?
        # グループタブページの更新時は処理スキップ
        logger.debug("=================== UsersController: update_with_autoresetrole")
        params[:tab] = 'general'
        logger.debug(params.to_yaml)
        logger.debug("----- cfが変更されたか？")
        user_ucf_vals = @user.custom_field_values.map{|c| c.to_s}   # cfの実データ
        input_ucf_vals = params[:user][:custom_field_values].values # cfの画面選択値
        logger.debug("*** UCF-values: `#{user_ucf_vals}` => `#{input_ucf_vals}`")
        # cfのどれかが更新されたらreset_role_userに飛ぶ
        if user_ucf_vals != input_ucf_vals
          return unless reset_role_user
        end
      end
      ###############################

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
        render_error l(:error_is_not_exist, name)
        return nil
      end
      ins[:id]
    end

    ### for update_with_autoresetrole
    #
    # ロール自動アサイン機能本体
    #
    def reset_role_user
      logger.debug("################ reset_role_user #################")
      logger.debug("*** params=#{params.inspect}")
      logger.debug("*** @user=#{@user.inspect}")
      corp_ucf_name ||= l(:label_part_parent_project) # "所属プロジェクト"
      thd_pjt_name ||= l(:label_thd_pjt_name)         # "THD"
      ippan_role_name ||= l(:label_ippan_role_name)   # "一般ユーザ"

      ### UserCustomField: 所属プロジェクトの存在チェック, 無かったら終了
      logger.debug("----- `#{corp_ucf_name}`が存在するか？")
      corp_ucf_id ||= is_exist_and_get_id(UserCustomField, corp_ucf_name) || return
      logger.debug("*** UserCustomField is `#{corp_ucf_name}`, ID=`#{corp_ucf_id}`")

      ### Role: 一般ユーザの存在チェック, 無かったら終了
      logger.debug("----- `#{ippan_role_name}`が存在するか？")
      ippan_role_id ||= is_exist_and_get_id(Role, ippan_role_name) || return
      logger.debug("*** reset-Role is `#{ippan_role_name}`, ID=`#{ippan_role_id}`")

      ### 所属未変更の場合はここで終了
      logger.debug("----- 所属プロジェクトが変更されたか？")
      user_ucf_val = @user.custom_field_values.detect{|c| c.custom_field.name == corp_ucf_name}
      input_ucf_val = params[:user][:custom_field_values][corp_ucf_id.to_s]
      logger.debug("*** UCF-value: `#{user_ucf_val}` => `#{input_ucf_val}`")
      return true if user_ucf_val.to_s == input_ucf_val

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
      return true unless input_ucf_val.present?

      ### 選択した所属に従って、親プロジェクトに一般ユーザを付与
      thd_pjt_id ||= is_exist_and_get_id(Project, thd_pjt_name)
      logger.debug("*** all allowed Project is `#{thd_pjt_name}`, ID=`#{thd_pjt_id}`")

      parent_pjts.each do |pjt|
        ### 親プロジェクト毎に、以下のルールでロール付与
        ### I'm THD. all PJTs OK.
        ### We're allowed THD-PJT.
        ### I'm allowed only My-PJT.
        if input_ucf_val == thd_pjt_name || pjt[:name] == thd_pjt_name || pjt[:name] == input_ucf_val
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
