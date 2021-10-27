# frozen_string_literal: true

class User < ApplicationRecord
  before_save { self.name = name.downcase }
  validates :name, presence: true,
                   length: { minimum: 3, maximum: 12 },
                   format: { with: /\A\w+\Z/i },
                   uniqueness: { case_sensitive: false }
end
