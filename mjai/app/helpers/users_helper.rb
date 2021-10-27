module UsersHelper
  def join(user)
    session[:user_id] = user.id
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def joined?
    !current_user.nil?
  end

  def leave
    current_user.destroy
    session.delete(:user_id)
    @current_user = nil
  end
end
