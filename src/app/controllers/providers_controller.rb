
#
# Copyright 2011 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

class ProvidersController < ApplicationController
  include AutoCompleteSearch
  include IndexedModel

  before_filter :find_rh_provider, :only => [:redhat_provider,:update_redhat_provider]

  before_filter :find_provider, :only => [:products_repos, :show, :edit, :update, :destroy]
  before_filter :authorize #after find_provider
  before_filter :panel_options, :only => [:index, :items]
  before_filter :search_filter, :only => [:auto_complete_search]

  respond_to :html, :js

  def section_id
    'contents'
  end

  def rules
    index_test = lambda{Provider.any_readable?(current_organization)}
    create_test = lambda{Provider.creatable?(current_organization)}
    read_test = lambda{@provider.readable?}
    edit_test = lambda{@provider.editable?}
    delete_test = lambda{@provider.deletable?}
    {
      :index => index_test,
      :items => index_test,
      :show => index_test,
      :auto_complete_search => index_test,
      :new => create_test,
      :create => create_test,
      :edit =>read_test,
      :update => edit_test,
      :destroy => delete_test,
      :products_repos => read_test,

      :redhat_provider =>read_test,
      :update_redhat_provider => edit_test
    }
  end

  def products_repos
    @products = @provider.products
    render :partial => "products_repos", :layout => "tupane_layout", :locals => {:provider => @provider,
                                         :providers => @providers, :products => @products, :editable=>@provider.editable?}
  end

  def update_redhat_provider
    if !params[:provider].blank? and params[:provider].has_key? :contents
      temp_file = nil
      begin
        dir = "#{Rails.root}/tmp"
        Dir.mkdir(dir) unless File.directory? dir
        temp_file = File.new(File.join(dir, "import_#{SecureRandom.hex(10)}.zip"), 'w+', 0600)
        temp_file.write params[:provider][:contents].read
        temp_file.close
        @provider.import_manifest File.expand_path(temp_file.path)
        notice _("Subscription manifest uploaded successfully for provider '%{name}'. Please enable the repositories you want to sync by selecting 'Enable Repositories' and selecting individual repositories to be enabled." % {:name => @provider.name}), {:synchronous_request => false}
      rescue Exception => error
        display_message = parse_display_message(error.response)
        error_text = _("Subscription manifest upload for provider '%{name}' failed." % {:name => @provider.name})
        error_text += _("%{newline}Reason: %{reason}" % {:reason => display_message, :newline => "<br />"}) unless display_message.blank?
        errors error_text
        Rails.logger.error "error uploading subscriptions."
        Rails.logger.error error
        Rails.logger.error error.backtrace.join("\n")
        # Fall-through even on error so that the import history is refreshed
      end
      redhat_provider
    else
      # user didn't provide a manifest to upload
      errors _("Subscription manifest must be specified on upload.")
      render :nothing => true
    end
  end

  def redhat_provider
    # We default to none imported until we can properly poll Candlepin for status of the import
    @grouped_subscriptions = []
    begin
      setup_subs
    rescue Exception => error
      display_message = parse_display_message(error.response)
      error_text = _("Unable to retrieve subscription manifest for provider '%{name}." % {:name => @provider.name})
      error_text += _("%{newline}Reason: %{reason}" % {:reason => display_message, :newline => "<br />"}) unless display_message.blank?
      errors error_text, {:synchronous_request => false}
      Rails.logger.error "Error fetching subscriptions from Candlepin"
      Rails.logger.error error
      Rails.logger.error error.backtrace.join("\n")
      render :template =>"providers/redhat/show", :status => :bad_request and return
    end

    begin
      @statuses = @provider.owner_imports
    rescue Exception => error
      @statuses = []
      display_message = parse_display_message(error.response)
      error_text = _("Unable to retrieve subscription history for provider '%{name}." % {:name => @provider.name})
      error_text += _("%{newline}Reason: %{reason}" % {:reason => display_message, :newline => "<br />"}) unless display_message.blank?
      errors error_text, {:synchronous_request => false}
      Rails.logger.error "Error fetching subscription history from Candlepin"
      Rails.logger.error error
      Rails.logger.error error.backtrace.join("\n")
      render :template =>"providers/redhat/show", :status => :bad_request and return
    end

    render :template =>"providers/redhat/show"
  end

  def items
    ids = Provider.readable(current_organization).collect{|p| p.id}
    render_panel_direct(Provider, @panel_options, params[:search], params[:offset], [:name, 'asc'],
                        {"id"=>ids, :provider_type=>[Provider::CUSTOM]})

    #render_panel_items(Provider.readable(current_organization).custom.order('providers.name'), @panel_options, params[:search], params[:offset])
  end

  def show
    provider = Provider.find(params[:id])
    render :partial=>"common/list_update", :locals=>{:item=>provider, :accessor=>"id", :columns=>['name']}
  end

  def edit
    render :partial => "edit", :layout => "tupane_layout", :locals => {:provider => @provider, :editable=>@provider.editable?,
                                                                       :name=>controller_display_name}
  end

  def new
    @provider = Provider.new
    render :partial => "new", :layout => "tupane_layout", :locals => {:provider => @provider}
  end

  def create
    begin
      @provider = Provider.create! params[:provider].merge({:provider_type => Provider::CUSTOM,
                                                                    :organization => current_organization})
      notice _("Provider '#{@provider['name']}' was created.")
      
      if Provider.where(:id => @provider.id).search_for(params[:search]).include?(@provider) 
        render :partial=>"common/list_item", :locals=>{:item=>@provider, :accessor=>"id", :columns=>['name'], :name=>controller_display_name}
      else
        notice _("'#{@provider["name"]}' did not meet the current search criteria and is not being shown."), { :level => 'message', :synchronous_request => false }
        render :json => { :no_match => true }
      end
    rescue Exception => error
      Rails.logger.error error.to_s
      errors error
      render :text => error, :status => :bad_request
    end
  end

  def destroy
    @id = @provider.id
    begin
      @provider.destroy
      if @provider.destroyed?
        notice _("Provider '#{@provider[:name]}' was deleted.")
        #render and do the removal in one swoop!
        render :partial => "common/list_remove", :locals => {:id=>params[:id], :name=>controller_display_name}
      else
        raise
      end
    rescue Exception => e
      errors e.to_s
    end
  end

  def update

    begin
      updated_provider = Provider.find(params[:id])
      result = params[:provider].values.first

      updated_provider.name = params[:provider][:name] unless params[:provider][:name].nil?

      unless params[:provider][:description].nil?
        result = updated_provider.description = params[:provider][:description].gsub("\n",'')
      end

      updated_provider.repository_url = params[:provider][:repository_url] unless params[:provider][:repository_url].nil?
      updated_provider.provider_type = params[:provider][:provider_type] unless params[:provider][:provider_type].nil?

      updated_provider.save!
      notice _("Provider '#{updated_provider.name}' was updated.")

      if not Provider.where(:id => updated_provider.id).search_for(params[:search]).include?(updated_provider)
        notice _("'#{updated_provider["name"]}' no longer matches the current search criteria."), { :level => 'message', :synchronous_request => false }
      end

      respond_to do |format|
        format.html { render :text => escape_html(result) }
      end

    rescue Exception => e
      errors e.to_s

      respond_to do |format|
        format.html { render :partial => "layouts/notification", :status => :bad_request, :content_type => 'text/html' and return}
        format.js { render :partial => "layouts/notification", :status => :bad_request, :content_type => 'text/html' and return}
      end
    end
  end

  protected

  def find_provider
    begin
      @provider = Provider.find(params[:id])
    rescue Exception => error
      errors error.to_s
      execute_after_filters
      render :text => error, :status => :bad_request
    end
  end

  def find_rh_provider
      @provider = current_organization.redhat_provider
  end


  def panel_options
        @panel_options = { :title => _('Providers'),
                 :col => ['name'],
                 :create => _('Provider'),
                 :name => controller_display_name,
                 :ajax_load => true,
                 :ajax_scroll=>items_providers_path(),
                 :enable_create=> Provider.creatable?(current_organization)}
        
  end

  def controller_display_name
    return _('provider')
  end

  def search_filter
    @filter = {:organization_id => current_organization}
  end

  def setup_subs
    # TODO: See subscriptions_controller#reformat_subscriptions for a better(?) OpenStruct implementation

    @provider = current_organization.redhat_provider
    all_subs = Candlepin::Owner.pools @provider.organization.cp_key
    # We default to none imported until we can properly poll Candlepin for status of the import
    @grouped_subscriptions = {}
    all_subs.each do |sub|
      # Subscriptions with the same 'stack_id' attribute are grouped together. Not all have this
      # attribute so the 'id' is used as a default since it will be unique between
      # subscriptions.
      #
      group_id = sub['id']
      sub['productAttributes'].each do |attr|
        if attr['name'] == 'stacking_id'
          group_id = attr['value']
        elsif attr['name'] == 'support_level'
          sub['support_level'] = attr['value']
        elsif attr['name'] == 'arch'
          sub['arch'] = attr['value']
        end
      end

      # Other interesting attributes
      sub['machine_type'] = ''
      sub['attributes'].each do |attr|
        if attr['name'] == 'virt_only'
          if attr['value'] == 'true'
            sub['machine_type'] = _('Virtual')
          elsif attr['value'] == 'false'
            sub['machine_type'] = _('Physical')
          end
        end
      end

      product = Product.where(:cp_id => sub['productId']).first
      if product and product.provider == @provider
        @grouped_subscriptions[group_id] ||= []
        @grouped_subscriptions[group_id] << sub if !@grouped_subscriptions[group_id].include? sub
      end
=begin TODO: Should the bundled products be displayed too?
      if sub['providedProducts'].length > 0
        sub['providedProducts'].each do |cp_product|
          product = Product.where(:cp_id => cp_product['productId']).first
          if product and product.provider == @provider
            @grouped_subscriptions[group_id] ||= []
            @grouped_subscriptions[group_id] << sub if !@grouped_subscriptions[group_id].include? sub
          end
        end
      else
        product = Product.where(:cp_id => sub['productId']).first
        if product and product.provider == @provider
          @grouped_subscriptions[group_id] ||= []
          @grouped_subscriptions[group_id] << sub if !@grouped_subscriptions[group_id].include? sub
        end
      end
=end
    end
  end
end
