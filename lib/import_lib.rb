# encoding: UTF-8

require 'fileutils'

class Importer  #{{{1

  def initialize(file_path)  #{{{2
    @file_path  = file_path
    @lof_errors = Array.new

    parse_data
  end

  def parse_data  #{{{2
    File.open(@file_path, 'rb') do |file|
      @raw_data = CSV.parse(file)

      @headers = @raw_data[0]
      @data = @raw_data[1..-1]
    end
  end

  def headers  #{{{2
    @raw_data[0]
  end

  def data  #{{{2
    @raw_data[1..-1]
  end

  def import  #{{{2
    @data.each do |row|
      section = row[@headers.index("Section")].to_sym

      case section
      when :KeyQuestion
      when :Publication
      when :DesignDetail
        _import_section_row(row, section)
      when :DiagnosticTest
      when :DiagnosticTestDetail
      when :Arm
      when :ArmDetail
      when :BaselineCharacteristic
      when :Outcome
      when :OutcomeDetail
      when :AdverseEvent
      when :QualityDimension
      when :QualityRating
      else 
        @lof_errors << "Failure to sort section #{section}"
      end
    end
  end

  def _import_section_row(row, section)  #{{{2
    info_hash = _get_info_hash(row, section)
    #!!! NEED TO CHECK FOR THIS CONDITION
    #if info_hash[:selected]
      _write_info_hash_to_db(section, info_hash)
    #end
  end

  def _write_info_hash_to_db(section, info_hash)
    dp = "#{section.to_s}DataPoint".constantize.find(:first,
            :conditions => { "#{section.to_s.underscore}_field_id".to_sym => info_hash[:section_detail_field_id],
                             :study_id => info_hash[:study_id],
                             :extraction_form_id => info_hash[:ef_id],
                             :subquestion_value => info_hash[:subquestion_value],
                             :row_field_id => info_hash[:row_field_id],
                             :column_field_id => info_hash[:col_field_id],
                             :arm_id => info_hash[:arm_id],
                             :outcome_id => info_hash[:outcome_id] })
    if dp.blank?
      "#{section.to_s}DataPoint".constantize.create("#{section.to_s.underscore}_field_id".to_sym => info_hash[:section_detail_field_id],
                                                    :value => info_hash[:value],
                                                    :notes => info_hash[:notes],
                                                    :study_id => info_hash[:study_id],
                                                    :extraction_form_id => info_hash[:ef_id],
                                                    :subquestion_value => info_hash[:subquestion_value],
                                                    :row_field_id => info_hash[:row_field_id],
                                                    :column_field_id => info_hash[:col_field_id],
                                                    :arm_id => info_hash[:arm_id],
                                                    :outcome_id => info_hash[:outcome_id])
    else
      dp.value = info_hash[:value]
      dp.notes = info_hash[:notes]
      dp.save
    end
  end

  def _get_info_hash(row, section)  #{{{2
    info_hash = Hash.new

    info_hash[:project_id]              = row[@headers.index("Project ID")].to_i
    info_hash[:ef_id]                   = _get_ef_id(row)
    info_hash[:section]                 = section
    info_hash[:study_id]                = row[@headers.index("Study ID")].to_i
    info_hash[:section_detail_field_id] = _get_section_detail_id(row)
    info_hash[:subquestion_value]       = row[@headers.index("Follow-up Value")]
    info_hash[:value]                   = row[@headers.index("Value")]
    info_hash[:notes]                   = row[@headers.index("Notes")]
    info_hash[:row_field_id]            = _get_row_field_id(row)
    info_hash[:col_field_id]            = _get_col_field_id(row)
    info_hash[:arm_id]                  = _get_arm_id(row)
    info_hash[:outcome_id]              = _get_outcome_id(row)
    #info_hash[:diagnostic_test_id]      = _get_diagnostic_test_id(row)

    return info_hash
  end

#  def _get_diagnostic_test_id(row)  #{{{2
#  end

  def _get_outcome_id(row)  #{{{2
    study_id = row[@headers.index("Study ID")].to_i
    title    = row[@headers.index("Outcome Title")]
    ef_id    = _get_ef_id(row)

    outcome = Outcome.find(:first, :conditions => {
            :study_id => study_id,
            :title => title,
            :extraction_form_id => ef_id })

    outcome_id = outcome.nil? ? 0 : outcome.id
    return outcome_id
  end

  def _get_arm_id(row)  #{{{2
    study_id = row[@headers.index("Study ID")].to_i
    title    = row[@headers.index("Arm Title")]
    ef_id    = _get_ef_id(row)

    arm = Arm.find(:first, :conditions => {
            :study_id => study_id,
            :title => title,
            :extraction_form_id => ef_id })

    arm_id = arm.nil? ? 0 : arm.id
    return arm_id
  end

  def _get_row_field_id(row)  #{{{2
    section_detail_id = _get_section_detail_id(row)
    row_option_text   = row[@headers.index("Row Option Text")]
    section  = row[@headers.index("Section")].to_sym

    row_field = "#{section}Field".constantize.find(:first, :conditions => {
            "#{section.to_s.underscore}_id".to_sym => section_detail_id,
            :option_text => row_option_text })

    row_field_id = row_field.nil? ? 0 : row_field.id
    return row_field_id
  end

  def _get_col_field_id(row)  #{{{2
    section_detail_id = _get_section_detail_id(row)
    col_option_text = row[@headers.index("Col Option Text")]
    section  = row[@headers.index("Section")].to_sym

    col_field = "#{section}Field".constantize.find(:first, :conditions => {
            "#{section.to_s.underscore}_id".to_sym => section_detail_id,
            :option_text => col_option_text })

    col_field_id = col_field.nil? ? 0 : col_field.id
    return col_field_id
  end

  def _get_ef_id(row)  #{{{2
    project_id = row[@headers.index("Project ID")].to_i
    ef_title   = row[@headers.index("EF Title")]

    ef_id = ExtractionForm.find_by_project_id_and_title(project_id, ef_title).id

    if ef_id.class != Fixnum
      puts "Too many ef ids found with ef id: #{ef_id}"
      @lof_errors << "Too many ef ids found with ef id: #{ef_id}"
      gets
    end

    return ef_id
  end

  def _get_section_detail_id(row)  #{{{2
    ef_id    = _get_ef_id(row)
    section  = row[@headers.index("Section")].to_sym
    question = row[@headers.index("Question")]

    section_detail_id = "#{section.to_s}".constantize.find_by_extraction_form_id_and_question(ef_id, question).id

    if section_detail_id.class != Fixnum
      puts "Too many section detail ids found for question id: #{question}"
      @lof_errors << "Too many section detail ids found for question id: #{question}"
      gets
    end

    return section_detail_id
  end
end
