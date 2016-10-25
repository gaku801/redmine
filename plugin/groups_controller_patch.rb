# encoding: utf-8

module GroupsControllerPatch
  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      unloadable
      alias_method_chain :update, :autoresetrole
    end
  end

  module InstanceMethods
    def update_with_autoresetrole
      ### add: ロール自動アサイン機能
      logger.debug("=================== GroupsController: update_with_autoresetrole")
      logger.debug(params.to_yaml)
      logger.debug(@group.to_yaml)
      logger.debug("----- cfが変更されたか？")
      group_gcf_vals = @group.custom_field_values.map{|c| c.to_s}  # cfの実データ
      input_gcf_vals = params[:group][:custom_field_values].values # cfの画面選択値
      logger.debug("*** GCF-values: `#{group_gcf_vals}` => `#{input_gcf_vals}`")
      if group_gcf_vals != input_gcf_vals
        # cfのどれかが更新されたらreset_role_groupに飛ぶ
        return unless reset_role_group
      end
      ###############################

      @group.safe_attributes = params[:group]

      respond_to do |format|
        if @group.save
          flash[:notice] = l(:notice_successful_update)
          format.html { redirect_to(groups_path) }
          format.api  { render_api_ok }
        else
          format.html { render :action => "edit" }
          format.api  { render_validation_errors(@group) }
        end
      end
    end

    private

    ### for update_with_autoresetrole
    # 親プロジェクトのロールリセット、ロール付与で使用
    # 指定したproject_idにアサインされているロールのm_idとrole_id(s)を返す
    # 未アサインならm_id=nil, role_ids=[]を返す
    def get_group_roles_by_projectid(project_id)
      g_memberships = @group.memberships.all(:conditions => ["project_id = ?", project_id])
      if g_memberships.present?
        g_m = g_memberships.first
        m_id = g_m[:id]
        role_ids = g_m.roles.map{|r| r[:id]}
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
    def reset_role_group
      logger.debug("################ reset_role_group #################")
      logger.debug("*** params=#{params.inspect}")
      logger.debug("*** @group=#{@group.inspect}")
      corp_gcf_name ||= l(:label_part_parent_project) # "所属プロジェクト"
      thd_pjt_name ||= l(:label_thd_pjt_name)         # "THD"
      ippan_role_name ||= l(:label_ippan_role_name)   # "一般ユーザ"

      ### GroupCustomField: 所属プロジェクトの存在チェック, 無かったら終了
      logger.debug("----- `#{corp_gcf_name}`が存在するか？")
      corp_gcf_id ||= is_exist_and_get_id(GroupCustomField, corp_gcf_name) || return
      logger.debug("*** GroupCustomField is `#{corp_gcf_name}`, ID=`#{corp_gcf_id}`")

      ### Role: 一般ユーザの存在チェック, 無かったら終了
      logger.debug("----- `#{ippan_role_name}`が存在するか？")
      ippan_role_id ||= is_exist_and_get_id(Role, ippan_role_name) || return
      logger.debug("*** reset-Role is `#{ippan_role_name}`, ID=`#{ippan_role_id}`")

      ### 所属未変更の場合はここで終了
      logger.debug("----- 所属プロジェクトが変更されたか？")
      group_gcf_val = @group.custom_field_values.detect{|c| c.custom_field.name == corp_gcf_name}
      input_gcf_val = params[:group][:custom_field_values][corp_gcf_id.to_s]
      logger.debug("*** UCF-value: `#{group_gcf_val}` => `#{input_gcf_val}`")
      return true if group_gcf_val.to_s == input_gcf_val

      ### 親プロジェクトから一般ユーザを削除
      logger.debug("----- 親プロジェクトにアサインされたロール一覧を取得")
      parent_pjts = Project.where(parent_id: nil)
      logger.debug("*** parent_pjts: #{parent_pjts.inspect}")
      logger.debug("@@@@@@ #{@group.memberships.to_yaml}")
      parent_pjts.each do |pjt|
        m_id, role_ids = get_group_roles_by_projectid(pjt[:id])
        logger.debug("*** get roles in #{pjt[:name]}(ID: #{pjt[:id]}) => #{[m_id, role_ids]}")

        ### 親プロジェクトにアサイン＆一般ユーザが存在の場合
        if m_id.present? && role_ids.delete(ippan_role_id)
          logger.debug("----- 一般ユーザを削除: #{pjt[:name]}")
          logger.debug("*** changed role_ids: #{role_ids}")
          membership = Member.edit_membership(m_id, {"role_ids" => role_ids}, @group)
          membership.save
        end
      end

      ### 所属なし選択の場合はここで終了
      return true unless input_gcf_val.present?

      ### 選択した所属に従って、親プロジェクトに一般ユーザを付与
      thd_pjt_id ||= is_exist_and_get_id(Project, thd_pjt_name)
      logger.debug("*** all allowed Project is `#{thd_pjt_name}`, ID=`#{thd_pjt_id}`")

      parent_pjts.each do |pjt|
        ### 親プロジェクト毎に、以下のルールでロール付与
        ### 1) I'm THD. all PJTs OK.
        ### 2) We're allowed THD-PJT.
        ### 3) I'm allowed only My-PJT.
        if input_gcf_val == thd_pjt_name || pjt[:name] == thd_pjt_name || pjt[:name] == input_gcf_val
          logger.debug("----- 一般ユーザを付与: #{pjt[:name]}")
          m_id, role_ids = get_group_roles_by_projectid(pjt[:id])
          role_ids.push(ippan_role_id)
          logger.debug("*** update Role: M_ID: #{m_id}, Roles: #{role_ids}")
          membership = Member.edit_membership(m_id, {"project_id"=>pjt[:id], "role_ids" => role_ids}, @group)
          membership.save
        end
      end
      logger.debug("###########################################")
    end
  end
end

GroupsController.send(:include, GroupsControllerPatch)
