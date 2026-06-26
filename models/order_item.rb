require_relative '../config/database'

class OrderItem < Sequel::Model
  many_to_one :order
  many_to_one :book
end
