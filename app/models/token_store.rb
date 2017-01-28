class TokenStore < ActiveRecord::Base
  belongs_to :user
  def load(_id)
    content || ""
  end

  # Put the token data into storage for the given ID.
  #
  # @param [String] id
  #  ID of token data to store.
  # @param [String] token
  #  The token data to store.
  def store(_id, _token)
    self.content = _token
    self.save
  end

  # Remove the token data from storage for the given ID.
  #
  # @param [String] id
  #  ID of the token data to delete
  def delete(_id)
    store("", nil)
  end
end