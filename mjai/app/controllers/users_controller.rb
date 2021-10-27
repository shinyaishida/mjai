class UsersController < ApplicationController
  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      join @user
      redirect_to room_path
    else
      flash.now[:danger] = "Invalid user name: #{@user.name}"
      render 'new'
    end
  end

  def destroy
    leave
    redirect_to join_path
  end

  private

  def user_params
    params.require(:user).permit(:name)
  end
end
