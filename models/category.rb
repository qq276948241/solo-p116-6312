require_relative '../config/database'

class Category < Sequel::Model
  plugin :validation_helpers
  plugin :tree, order: :position
  plugin :dirty

  one_to_many :books

  UNCATEGORIZED_NAME = '未分类'
  UNCATEGORIZED_CODE = 'uncategorized'

  def validate
    super
    validates_presence [:name]
    validates_unique [:code], allow_nil: true
    validates_numeric [:level, :position], allow_nil: true
  end

  def before_create
    super
    self.level ||= parent ? parent.level + 1 : 1
    self.position ||= (Category.where(parent_id: parent_id).max(:position) || 0) + 1
    self.is_leaf = children_dataset.count == 0 if is_leaf.nil?
  end

  def before_save
    super
    if changed_columns.include?(:parent_id) && parent
      self.level = parent.level + 1
    end
  end

  def after_save
    super
    if changed_columns.include?(:parent_id) && column_changes[:parent_id]
      old_parent_id = column_changes[:parent_id][0]
      if old_parent_id
        parent_was = Category[old_parent_id]
        parent_was&.update(is_leaf: parent_was.children_dataset.count == 0) if parent_was
      end
    end
    parent&.update(is_leaf: false) if parent
  end

  def after_destroy
    super
    books.update(category_id: Category.uncategorized_id)
    parent&.update(is_leaf: parent.children_dataset.count == 0) if parent
  end

  def leaf?
    is_leaf
  end

  def root?
    parent_id.nil?
  end

  def serializable_hash
    {
      id: id,
      parent_id: parent_id,
      name: name,
      code: code,
      level: level,
      position: position,
      is_leaf: is_leaf,
      books_count: books_dataset.count,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def serializable_tree
    data = serializable_hash
    kids = children_dataset.order(:position).all
    if kids.any?
      data[:children] = kids.map(&:serializable_tree)
    end
    data
  end

  def self.uncategorized_id
    cat = where(name: UNCATEGORIZED_NAME, code: UNCATEGORIZED_CODE).first
    unless cat
      cat = create(
        name: UNCATEGORIZED_NAME,
        code: UNCATEGORIZED_CODE,
        level: 1,
        position: 0,
        is_leaf: true
      )
    end
    cat.id
  end

  def self.uncategorized
    where(name: UNCATEGORIZED_NAME, code: UNCATEGORIZED_CODE).first ||
      create(
        name: UNCATEGORIZED_NAME,
        code: UNCATEGORIZED_CODE,
        level: 1,
        position: 0,
        is_leaf: true
      )
  end

  def self.root_nodes
    where(parent_id: nil).order(:position).all
  end

  def self.tree
    roots = root_nodes
    roots.map do |root|
      build_tree(root)
    end
  end

  def self.build_tree(node)
    data = node.serializable_hash
    kids = Category.where(parent_id: node.id).order(:position).all
    if kids.any?
      data[:children] = kids.map { |k| build_tree(k) }
    end
    data
  end

  def self.available_parents(exclude_id = nil)
    dataset = where(level: [1, 2]).order(:level, :position)
    dataset = dataset.where { id != exclude_id } if exclude_id
    dataset.all
  end

  def self.assign_uncategorized_to_orphan_books!
    uncategorized_id = self.uncategorized_id
    Book.where(category_id: nil).update(category_id: uncategorized_id)
  end
end
