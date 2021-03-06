module Edition::AuditTrail
  extend ActiveSupport::Concern

  class << self
    attr_accessor :whodunnit
  end

  def self.acting_as(actor)
    original_actor = Edition::AuditTrail.whodunnit
    Edition::AuditTrail.whodunnit = actor
    yield
  ensure
    Edition::AuditTrail.whodunnit = original_actor
  end

  included do
    has_many :versions, -> { order("created_at ASC, id ASC") }, as: :item

    has_one :most_recent_version,
            -> { order("versions.created_at DESC, versions.id DESC") },
            class_name: "Version",
            as: :item
    has_one :last_author,
            through: :most_recent_version,
            source: :user

    after_create  :record_create
    before_update :record_update
  end

  def edition_remarks_trail(edition_serial_number = 0)
    editorial_remarks.map { |r|
      EditorialRemarkAuditEntry.new(edition_serial_number, self, r)
    }.sort
  end

  def edition_version_trail(edition_serial_number = 0, superseded: true)
    scope = versions
    scope = scope.where.not(state: "superseded") unless superseded

    scope.map { |v|
      VersionAuditEntry.new(edition_serial_number, self, v)
    }.sort
  end

  def document_remarks_trail(superseded: true)
    document_trail(superseded: superseded, remarks: true)
  end

  def document_version_trail(superseded: true)
    document_trail(superseded: superseded, versions: true)
  end

  def latest_version_audit_entry_for(state)
    edition_version_trail.reverse.detect { |audit_entry| audit_entry.version.state == state }
  end

  def most_recent_submission_audit_entry
    matching_entry = nil
    edition_version_trail.reverse.map do |audit_entry|
      if audit_entry.version.state == "submitted"
        matching_entry = audit_entry
      elsif matching_entry.present?
        break
      end
    end
    matching_entry
  end

  def publication_audit_entry
    document_version_trail.detect { |audit_entry| audit_entry.version.state == "published" }
  end

private

  def record_create
    user = Edition::AuditTrail.whodunnit
    versions.create! event: "create", user: user, state: state
    alert!(user)
  end

  def record_update
    if changed.any?
      user = Edition::AuditTrail.whodunnit
      versions.build event: "update", user: user, state: state
      alert!(user)
    end
  end

  def alert!(user)
    if user && should_alert_for?(user)
      ::MailNotifications.edition_published_by_monitored_user(user).deliver_now
    end
  end

  def should_alert_for?(user)
    ENV["CO_NSS_WATCHKEEPER_EMAIL_ADDRESS"].present? &&
      user.email == ENV["CO_NSS_WATCHKEEPER_EMAIL_ADDRESS"]
  end

  def document_trail(superseded: true, versions: false, remarks: false)
    scope = document.editions

    scope = scope.includes(versions: [:user]) if versions
    scope = scope.includes(editorial_remarks: [:author]) if remarks

    scope
      .includes(versions: [:user])
      .order("created_at asc, id asc")
      .map.with_index { |edition, i|
        [
          (edition.edition_version_trail(i, superseded: superseded) if versions),
          (edition.edition_remarks_trail(i) if remarks),
        ].compact
      }.flatten
  end

  class AuditEntry
    extend ActiveModel::Naming

    delegate :created_at, :to_key, to: :@object

    attr_reader :edition_serial_number, :edition, :object

    def initialize(edition_serial_number, edition, object)
      @edition_serial_number = edition_serial_number
      @edition = edition
      @object = object
    end

    def <=>(other)
      [created_at, sort_priority] <=> [other.created_at, other.sort_priority]
    end

    def ==(other)
      other.class == self.class &&
        other.edition_serial_number == edition_serial_number &&
        other.edition == edition &&
        other.object == object
    end

    def first_edition?
      edition_serial_number.zero?
    end

    def sort_priority
      0
    end
  end

  class VersionAuditEntry < AuditEntry
    def self.model_name
      ActiveModel::Name.new(Version, nil)
    end

    alias_method :version, :object

    def sort_priority
      3
    end

    def action
      previous_state = version.previous && version.previous.state
      case version.event
      when "create"
        first_edition? ? "created" : "editioned"
      else
        previous_state != version.state ? version.state : "updated"
      end
    end

    def actor
      version.user
    end
  end

  class EditorialRemarkAuditEntry < AuditEntry
    def self.model_name
      ActiveModel::Name.new(EditorialRemark, nil)
    end

    alias_method :editorial_remark, :object

    def action
      "editorial_remark"
    end

    def actor
      editorial_remark.author
    end

    def message
      editorial_remark.body
    end

    def sort_priority
      2
    end
  end
end
