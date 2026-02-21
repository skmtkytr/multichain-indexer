class IndexerCursor < ApplicationRecord
  validates :chain_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[running stopped error] }

  scope :active, -> { where(status: "running") }

  def running?
    status == "running"
  end

  def mark_running!
    update!(status: "running", error_message: nil)
  end

  def mark_stopped!
    update!(status: "stopped")
  end

  def mark_error!(message)
    update!(status: "error", error_message: message)
  end

  def advance!(block_number)
    update!(last_indexed_block: block_number)
  end
end
