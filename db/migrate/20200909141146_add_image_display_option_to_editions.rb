class AddImageDisplayOptionToEditions < ActiveRecord::Migration[5.1]
  EDITIONS_TYPES_WITH_NO_IMAGES = ["CorporateInformationPage", "DocumentCollection", "StatisticalDataSet"].freeze

  def change
    add_column :editions, :image_display_option, :string, default: "organisation_image"
    
    editions_with_images = Edition.find_by_sql(["SELECT e.* FROM editions e LEFT OUTER JOIN images ON e.id = images.edition_id WHERE type in ('CaseStudy', 'Consultation', 'DetailedGuide', 'FatalityNotice', 'NewsArticle', 'Publication', 'Speech') AND images.id IS NOT NULL"])
    editions_with_images.each do | edition |
      edition.update_columns(use_organisation_image: "custom_image")
    end

    edition_scope = Edition.where(type: EDITIONS_TYPES_WITH_NO_IMAGES)
    edition_scope.update_all(use_organisation_image: "no_image")
  end
end