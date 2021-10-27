# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  include UsersHelper
  before_action :set_action_cable_identifier

  private

  def set_action_cable_identifier
    cookies.encrypted[:user_id] = current_user&.id
  end
end
