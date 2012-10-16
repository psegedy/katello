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

require 'rest_client'

class Api::ChangesetsContentController < Api::ApiController

  before_filter :find_product, :only => [:add_product, :remove_product, :add_package, :remove_package, :add_erratum,
                                         :remove_erratum, :add_distribution, :remove_distribution]
  before_filter :find_changeset!
  before_filter :authorize

  def rules
    manage_perm = lambda { @changeset.environment.changesets_manageable? }
    { :add_product         => manage_perm,
      :remove_product      => manage_perm,
      :add_package         => manage_perm,
      :remove_package      => manage_perm,
      :add_erratum         => manage_perm,
      :remove_erratum      => manage_perm,
      :add_repo            => manage_perm,
      :remove_repo         => manage_perm,
      :add_template        => manage_perm,
      :remove_template     => manage_perm,
      :add_distribution    => manage_perm,
      :remove_distribution => manage_perm,
    }
  end

  api :POST, "/changesets/:changeset_id/products", "Add a product to a changeset"
  param :product_id, :number, :desc => "The id of the product which should be added"
  def add_product
    @changeset.add_product! @product
    render :text => _("Added product '%s'") % @product.name, :status => 200
  end

  api :DELETE, "/changesets/:changeset_id/products/:id", "Removes a product from a changeset"
  param :content_id, :number, :desc => "The id of the product to remove"
  def remove_product
    render_after_removal @changeset.remove_product!(@product),
                         :success   => _("Removed product '%s'") % params[:id],
                         :not_found => _("Product %s not found in the changeset.") % params[:id]
  end

  api :POST, "/changesets/:changeset_id/packages", "Add a package to a changeset"
  param :name, String, :desc => "The nvrea of the package to add"
  param :product_id, :number, :desc => "The id of the product which contains the package"
  def add_package
    @changeset.add_package!(params[:name], @product)
    render :text => _("Added package '%s'") % params[:name], :status => 200
  end

  api :DELETE, "/changesets/:changeset_id/packages/:id", "Remove a package from a changeset"
  param :product_id, :number, :desc => "The id of the product which contains the package"
  def remove_package
    render_after_removal @changeset.remove_package!(params[:id], @product),
                         :success   => _("Removed package '%s'") % params[:id],
                         :not_found => _("Package '%s' not found in the changeset") % params[:id]
  end

  api :POST, "/changesets/:changeset_id/errata", "Add an errata to a changeset"
  param :erratum_id, :number, :desc => "The id of the errata to add"
  param :product_id, :number, :desc => "The product which contains the errata"
  def add_erratum
    @changeset.add_erratum!(params[:erratum_id], @product)
    render :text => _("Added erratum '%s'") % params[:erratum_id], :status => 200
  end

  api :DELETE, "/changesets/:changeset_id/errata/:id", "Remove an errata from a changeset"
  param :product_id, :number, :desc => "The product which contains the errata"
  def remove_erratum
    render_after_removal @changeset.remove_erratum!(params[:id], @product),
                         :success   => _("Removed erratum '%s'") % params[:id],
                         :not_found => _("Erratum '%s' not found in the changeset") % params[:id]
  end

  api :POST, "/changesets/:changeset_id/repositories", "Add a repository to a changeset"
  param :repository_id, :number, :desc => "The id of the repository to add"
  def add_repo
    repository = Repository.find(params[:repository_id])
    @changeset.add_repository!(repository)
    render :text => _("Added repository '%s'") % repository.name, :status => 200
  end

  api :DELETE, "/changesets/:changeset_id/repositories/:id", "Remove a repository from a changeset"
  def remove_repo
    repository = Repository.find(params[:id])
    render_after_removal @changeset.remove_repository!(repository),
                         :success   => _("Removed repository '%s'") % params[:id],
                         :not_found => _("Repository '%s' not found in the changeset") % params[:id]
  end

  api :POST, "/changesets/:changeset_id/templates", "Add a template to a changeset"
  param :template_id, :number, :desc => "The id of the template to add"
  def add_template
    template = SystemTemplate.find(params[:template_id])
    @changeset.add_template!(template)
    render :text => _("Added template '%s'") % template.name, :status => 200
  end

  api :DELETE, "/changesets/:changeset_id/templates/:id", "Remove a template from a changeset"
  def remove_template
    template = SystemTemplate.find(params[:id])
    render_after_removal @changeset.remove_template!(template),
                         :success   => _("Removed template '%s'") % params[:id],
                         :not_found => _("Template '%s' not found in the changeset") % params[:id]
  end

  api :POST, "/changesets/:changeset_id/distributions", "Add a distribution to a changeset"
  param :distribution_id, :number, :desc => "The id of the distribution to add"
  param :product_id, :number, :desc => "The product which contains the distribution"
  def add_distribution
    @changeset.add_distribution!(params[:distribution_id], @product)
    render :text => _("Added distribution '%s'") % params[:distribution_id]
  end

  api :DELETE, "/changesets/:changeset_id/distributions/:id", "Remove a distribution from a changeset"
  def remove_distribution
    render_after_removal @changeset.remove_distribution!(params[:id], @product),
                         :success   => _("Removed distribution '%s'") % params[:id],
                         :not_found => _("Distribution '%s' not found in the changeset") % params[:id]
  end

  private

  def find_changeset!
    @changeset = Changeset.find_by_id(params[:changeset_id]) or
        raise HttpErrors::NotFound, _("Couldn't find changeset '%s'") % params[:changeset_id]
  end

  def render_after_removal(removed_objects, options = { })
    render(unless removed_objects.blank?
             { :text => (options[:success] or raise ArgumentError), :status => 200 }
           else
             { :text => (options[:not_found] or raise ArgumentError), :status => 404 }
           end)
  end

  def find_product
    product_id = nil
    if params[:product_id]
      product_id = params[:product_id]
    elsif params[:id]
      product_id = params[:id]
    end
    @product = Product.find_by_cp_id(product_id) unless product_id.nil?
    raise HttpErrors::NotFound, _("Couldn't find product with id '%s'") % product_id if @product.nil?
  end
end
