# encoding: UTF-8

require 'fileutils'
require 'iconv' unless String.method_defined?(:encode)

class Importer  #{{{1

  def initialize(file_path)  #{{{2
    @file_path  = file_path
    @lof_errors = Array.new
    @affirm = ['Yes', 'yes', 'YES', 'Y', 'y']

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

  def _get_ef_id(project_id, ef_title)  #{{{2
    ExtractionForm.find_by_title_and_project_id(ef_title, project_id).id
  end

  def _get_arm_id(study_id, title, extraction_form_id)  #{{{2
    arm = Arm.find_by_study_id_and_title_and_extraction_form_id(study_id, title, extraction_form_id)
    if arm.blank?
      return 0
    else
      return arm.id
    end
  end

  def _get_arm_title(row)  #{{{2
    begin
      arm_title = row[@headers.index("Arm Title")]
    rescue
      arm_title = ""
    end

    return arm_title
  end

  def _get_outcome_id(study_id, title, extraction_form_id)  #{{{2
    outcome = Outcome.find_by_study_id_and_title_and_extraction_form_id(study_id, title, extraction_form_id)
    if outcome.blank?
      return 0
    else
      return outcome.id
    end
  end

  def _get_outcome_title(row)  #{{{2
    begin
      outcome_title = row[@headers.index("Outcome Title")]
    rescue
      outcome_title = ""
    end

    return outcome_title
  end

  def _get_diagnostic_test_id(study_id, title, extraction_form_id)  #{{{2
    dt = DiagnosticTest.find_by_study_id_and_title_and_extraction_form_id(study_id, title, extraction_form_id)
    if dt.blank?
      return 0
    else
      return dt.id
    end
  end

  def _get_diagnostic_test_title(row)  #{{{2
    begin
      dt_title = row[@headers.index("Diagnostic Test Title")]
    rescue
      dt_title = ""
    end

    return dt_title
  end

  def _get_section_detail_field_id(section, question, ef_id, type)  #{{{2
    "#{section.to_s}".constantize.find(:first, :conditions => { :question => question,
                                                                :extraction_form_id => ef_id,
                                                                :field_type => type }).id
  end

  def _get_row_field_id(section, section_detail_field_id, row_option_text)  #{{{2
    begin
      row_field_id = "#{section.to_s}Field".constantize.find(:first, :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail_field_id,
                                                                                      :option_text => row_option_text,
                                                                                      :column_number => 0 }).id
    rescue
      row_field_id = 0
    end

    return row_field_id
  end

  def _get_col_field_id(section, section_detail_field_id, col_option_text)  #{{{2
    begin
      col_field_id = "#{section.to_s}Field".constantize.find(:first, :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail_field_id,
                                                                                      :option_text => col_option_text,
                                                                                      :row_number => 0 }).id
    rescue
      col_field_id = 0
    end

    return col_field_id
  end

  def import  #{{{2
    @data.each do |row|
      section = row[@headers.index("Section")]
      case section
      when "Arm"
      when "Outcome"
        process_outcomes(row, section)
      when "QualityDimension"
        process_quality_dimension(row, section)
      when "QualityRating"
      else
        selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
        type = row[@headers.index("Question Type")]
        if @affirm.include?(selected) || type=='text'
          process_details(row, section, selected, type)
        end
      end

#      case type
#      when "text"
#        _import_text(ef_id, section, row)
#      when "select"
#        _import_select(ef_id, section, row)
#      when "radio"
#        _import_radio(ef_id, section, row)
#      when "checkbox"
#        _import_checkbox(ef_id, section, row)
#      when "matrix_radio"
#        _import_matrix_radio(ef_id, section, row)
#      when "matrix_checkbox"
#        _import_matrix_checkbox(ef_id, section, row)
#      when "matrix_select"
#        _import_matrix_select(ef_id, section, row)
#      else
#        @lof_errors << "Failure to sort question type: #{type}"
#      end
    end
  end

  def process_outcomes(row, section)  #{{{2
    datapoint_info = Hash.new
    datapoint_info[:project_id] = row[@headers.index("Project ID")].to_i
    datapoint_info[:ef_title] = _clean_string row[@headers.index("EF Title")]
    datapoint_info[:outcome_id] = row[@headers.index("Outcome ID")].to_i
    datapoint_info[:subgroup_id] = row[@headers.index("Subgroup ID")].to_i
    datapoint_info[:timepoint_id] = row[@headers.index("Timepoint ID")].to_i
    datapoint_info[:study_id] = row[@headers.index("Study ID")].to_i
    datapoint_info[:outcome_title] = _clean_string row[@headers.index("Outcome Title")]
    datapoint_info[:outcome_description] = _clean_string row[@headers.index("Outcome Description")]
    datapoint_info[:outcome_type] = _clean_string row[@headers.index("Outcome Type")]
    datapoint_info[:outcome_units] = _clean_string row[@headers.index("Outcome Units")]
    datapoint_info[:outcome_notes] = _clean_string row[@headers.index("Outcome Notes")]
    datapoint_info[:subgroup] = _clean_string row[@headers.index("Population")]
    datapoint_info[:subgroup_description] = _clean_string row[@headers.index("Population Description")]
    datapoint_info[:timepoint] = _clean_string row[@headers.index("Timepoint")]
    datapoint_info[:time_unit] = _clean_string row[@headers.index("Time Unit")]
    datapoint_info[:ef_id] = _get_ef_id(datapoint_info[:project_id], datapoint_info[:ef_title])

    outcome_id = _update_db_outcomes(datapoint_info)
    _update_db_timepoints(datapoint_info, outcome_id)
    _update_db_subgroups(datapoint_info, outcome_id)
  end

  def _clean_string(string)  #{{{2
    unless string.blank?
      file_contents = string
      if String.method_defined?(:encode)
        file_contents.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
        file_contents.encode!('UTF-8', 'UTF-16')
      else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        file_contents = ic.iconv(file_contents)
      end
      string = file_contents
    end

    return string
  end

  def _update_db_subgroups(info, outcome_id)  #{{{2
    subgroup_id = info[:subgroup_id]
    subgroup_description = info[:subgroup_description]
    subgroup = info[:subgroup]
    
    if subgroup_id==0
      # Try to find it by title first
      s = OutcomeSubgroup.find(:first, :conditions => { :outcome_id => outcome_id,
                                                        :title => subgroup })
      if s.blank?
        # Create new subgroup
        s = OutcomeSubgroup.create(:outcome_id => outcome_id,
                                   :title => subgroup,
                                   :description => subgroup_description)
      end
    else
      s = OutcomeSubgroup.find(subgroup_id)
    end

    s.title = subgroup
    s.description = subgroup_description
    s.save
  end

  def _update_db_timepoints(info, outcome_id)  #{{{2
    timepoint_id = info[:timepoint_id]
    time_unit = info[:time_unit]
    timepoint = info[:timepoint]
    
    if timepoint_id==0
      # Try to find it by title first
      t = OutcomeTimepoint.find(:first, :conditions => { :outcome_id => outcome_id,
                                                         :number => timepoint,
                                                         :time_unit => time_unit })
      if t.blank?
        # Create new timepoint
        OutcomeTimepoint.create(:outcome_id => outcome_id,
                                :number => timepoint,
                                :time_unit => time_unit)
      end
    else
      t = OutcomeTimepoint.find(timepoint_id)
    end

    t.number = timepoint
    t.time_unit = time_unit
    t.save
  end

  def _update_db_outcomes(info)  #{{{2
    outcome_id = info[:outcome_id]
    study_id = info[:study_id]
    outcome_title = info[:outcome_title]
    units = info[:outcome_units]
    description = info[:outcome_description]
    notes = info[:outcome_notes]
    outcome_type = info[:outcome_type]
    ef_id = info[:ef_id]

    if outcome_id==0
      outcome_id = _get_outcome_id(study_id, outcome_title, ef_id)
      if outcome_id==0
        # Create a new outcome
        outcome = Outcome.create(:study_id => study_id,
                                 :title => outcome_title,
                                 :is_primary => 1,
                                 :units => units,
                                 :description => description,
                                 :notes => notes,
                                 :outcome_type => outcome_type,
                                 :extraction_form_id => ef_id)
        outcome_id = outcome.id
      else
        outcome = Outcome.find(outcome_id)
      end
    else
      outcome = Outcome.find(outcome_id)
    end

    outcome.title = outcome_title
    outcome.units = units
    outcome.description = description
    outcome.notes = notes
    outcome.outcome_type = outcome_type
    outcome.save

    return outcome.id
  end

  def process_quality_dimension(row, section)  #{{{2
    project_id              = row[@headers.index("Project ID")].to_i
    project_title           = row[@headers.index("Project Title")]
    ef_title                = row[@headers.index("EF Title")]
    ef_id                   = _get_ef_id(project_id, ef_title)
    study_id                = row[@headers.index("Study ID")].to_i
    question                = row[@headers.index("Dimension")]
    section_detail_field_id = _get_quality_dimension_field_id(section, question, ef_id)
    value                   = row[@headers.index("Value")]
    unless value.blank?
      file_contents = value
      if String.method_defined?(:encode)
        file_contents.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
        file_contents.encode!('UTF-8', 'UTF-16')
      else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        file_contents = ic.iconv(file_contents)
      end
      value = file_contents
    end
    notes                   = row[@headers.index("Notes")]
    unless notes.blank?
      file_contents = notes
      if String.method_defined?(:encode)
        file_contents.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
        file_contents.encode!('UTF-8', 'UTF-16')
      else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        file_contents = ic.iconv(file_contents)
      end
      notes = file_contents
    end
    datapoint_id            = row[@headers.index("Data Point ID")].to_i
  
    datapoint_info = Hash.new
    datapoint_info[:section_detail_field_id] = section_detail_field_id
    datapoint_info[:value] = value
    datapoint_info[:notes] = notes
    datapoint_info[:study_id] = study_id
    datapoint_info[:extraction_form_id] = ef_id
    datapoint_info[:datapoint_id] = datapoint_id

    update_db_quality_dimension(section, datapoint_info)
  end

  def _get_quality_dimension_field_id(section, question, ef_id)  #{{{2
    "#{section.to_s}Field".constantize.find(:first, :conditions => { :title => question,
                                                                     :extraction_form_id => ef_id }).id
  end

  def process_details(row, section, selected, type)  #{{{2
    project_id              = row[@headers.index("Project ID")].to_i
    project_title           = row[@headers.index("Project Title")]
    ef_title                = row[@headers.index("EF Title")]
    ef_id                   = _get_ef_id(project_id, ef_title)
    study_id                = row[@headers.index("Study ID")].to_i
  
    arm_title               = _get_arm_title(row)
    if arm_title.blank?
      arm_id                = 0
    else
      arm_id                = _get_arm_id(study_id, arm_title, ef_id)
    end
  
    outcome_title           = _get_outcome_title(row)
    if outcome_title.blank?
      outcome_id            = 0
    else
      outcome_id            = _get_outcome_id(study_id, outcome_title, ef_id)
    end
  
    diagnostic_test_title   = _get_diagnostic_test_title(row)
    if diagnostic_test_title.blank?
      diagnostic_test_id    = 0
    else
      diagnostic_test_id    = _get_diagnostic_test_id(study_id, diagnostic_test_title, ef_id)
    end
  
    question                = row[@headers.index("Question")]
    section_detail_field_id = _get_section_detail_field_id(section, question, ef_id, type)
    value                   = row[@headers.index("Value")]
    unless value.blank?
      file_contents = value
      if String.method_defined?(:encode)
        file_contents.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
        file_contents.encode!('UTF-8', 'UTF-16')
      else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        file_contents = ic.iconv(file_contents)
      end
      value = file_contents
    end
    selected                = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
    notes                   = row[@headers.index("Notes")]
    unless notes.blank?
      file_contents = notes
      if String.method_defined?(:encode)
        file_contents.encode!('UTF-16', 'UTF-8', :invalid => :replace, :replace => '')
        file_contents.encode!('UTF-8', 'UTF-16')
      else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        file_contents = ic.iconv(file_contents)
      end
      notes = file_contents
    end
    subquestion_value       = row[@headers.index("Follow-up Value")]
    row_option_text         = row[@headers.index("Row Option Text")]
    row_field_id            = _get_row_field_id(section, section_detail_field_id, row_option_text)
    col_option_text         = row[@headers.index("Col Option Text")]
    column_field_id         = _get_col_field_id(section, section_detail_field_id, col_option_text)
    datapoint_id            = row[@headers.index("Data Point ID")].to_i
  
    datapoint_info = Hash.new
    datapoint_info[:section_detail_field_id] = section_detail_field_id
    datapoint_info[:value] = value
    datapoint_info[:notes] = notes
    datapoint_info[:study_id] = study_id
    datapoint_info[:extraction_form_id] = ef_id
    datapoint_info[:subquestion_value] = subquestion_value
    datapoint_info[:row_field_id] = row_field_id
    datapoint_info[:column_field_id] = column_field_id
    datapoint_info[:arm_id] = arm_id
    datapoint_info[:outcome_id] = outcome_id
    datapoint_info[:diagnostic_test_id] = diagnostic_test_id
    datapoint_info[:datapoint_id] = datapoint_id

    update_db(section, datapoint_info)
  end

  def update_db_quality_dimension(section, dp)  #{{{2
    if dp[:datapoint_id]==0 || dp[:datapoint_id].blank?
      # Try to find the datapoint first and then update. If it cannot be found then just create
      if dp[:section]==:DiagnosticTest
        #!!!
      else
        datapoint = "#{section.to_s}DataPoint".constantize.find(:first, :conditions => {
                "#{section.to_s.underscore}_field_id".to_sym => dp[:section_detail_field_id],
                :value                                       => dp[:value],
                :study_id                                    => dp[:study_id],
                :extraction_form_id                          => dp[:extraction_form_id] })
        if datapoint.blank?
          datapoint = "#{section.to_s}DataPoint".constantize.create(
                  "#{section.to_s.underscore}_field_id".to_sym => dp[:section_detail_field_id],
                  :value                                       => dp[:value],
                  :notes                                       => dp[:notes],
                  :study_id                                    => dp[:study_id],
                  :extraction_form_id                          => dp[:extraction_form_id])
        else
          datapoint.value = dp[:value]
          datapoint.notes = dp[:notes]
          datapoint.save
        end
      end
    else
      # Update the existing value
      datapoint = "#{section.to_s}DataPoint".constantize.find(dp[:datapoint_id])
      datapoint.value = dp[:value]
      datapoint.notes = dp[:notes]
      datapoint.save
    end
  end

  def update_db(section, dp)  #{{{2
    if dp[:datapoint_id]==0 || dp[:datapoint_id].blank?
      # Try to find the datapoint first and then update. If it cannot be found then just create
      if dp[:section]==:DiagnosticTest
        #!!!
      else
        datapoint = "#{section.to_s}DataPoint".constantize.find(:first, :conditions => {
                "#{section.to_s.underscore}_field_id".to_sym => dp[:section_detail_field_id],
                :value                                       => dp[:value],
                :study_id                                    => dp[:study_id],
                :extraction_form_id                          => dp[:extraction_form_id],
                :row_field_id                                => dp[:row_field_id],
                :column_field_id                             => dp[:column_field_id],
                :arm_id                                      => dp[:arm_id],
                :outcome_id                                  => dp[:outcome_id] })
        if datapoint.blank?
          datapoint = "#{section.to_s}DataPoint".constantize.create(
                  "#{section.to_s.underscore}_field_id".to_sym => dp[:section_detail_field_id],
                  :value                                       => dp[:value],
                  :notes                                       => dp[:notes],
                  :study_id                                    => dp[:study_id],
                  :extraction_form_id                          => dp[:extraction_form_id],
                  :subquestion_value                           => dp[:subquestion_value],
                  :row_field_id                                => dp[:row_field_id],
                  :column_field_id                             => dp[:column_field_id],
                  :arm_id                                      => dp[:arm_id],
                  :outcome_id                                  => dp[:outcome_id] )
        else
          datapoint.value = dp[:value]
          datapoint.notes = dp[:notes]
          datapoint.subquestion_value = dp[:subquestion_value]
          datapoint.save
        end
      end
    else
      # Update the existing value
      datapoint = "#{section.to_s}DataPoint".constantize.find(dp[:datapoint_id])
      datapoint.value = dp[:value]
      datapoint.notes = dp[:notes]
      datapoint.subquestion_value = dp[:subquestion_value]
      datapoint.save
    end
  end

#  def _import_text(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#    value = row[@headers.index("Value")]
#
#    if @affirm.include? selected
#      if dp_id==0
#        dp = _get_text_datapoint_entry(ef_id, section, row)
#        dp_id = dp.id
#      end
#
#      params = { :section => section,
#                 :datapoint_id => dp_id,
#                 :value => value }
#      _update_db(params)
#    end
#  end

#  def _get_text_datapoint_entry(ef_id, section, row)  #{{{2
#    section_detail_field_id = _get_section_detail_field_id(ef_id, section, row).to_i
#    study_id = row[@headers.index("Study ID")].to_i
#    extraction_form_id = ef_id
#    arm_id = _get_arm_id()
#    outcome_id
#    diagnostic_test_id
#  end
#
#  def _update_db(params)  #{{{2
#    section = params[:section]
#    datapoint_id = params[:datapoint_id]
#    value = params[:value]
#
#    dp = "#{section}DataPoint".constantize.find(datapoint_id)
#    dp.value = value
#    dp.save
#  end

#  def _import_select(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

#  def _import_radio(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

#  def _import_checkbox(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

#  def _import_matrix_radio(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

#  def _import_matrix_checkbox(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

#  def _import_matrix_select(ef_id, section, row)  #{{{2
#    #!!!
#    dp_id = row[@headers.index("Data Point ID")].to_i
#    selected = row[@headers.index("Selected? (Y=Yes, *Blank*=No)")]
#
#    if @affirm.include? selected
#      p dp_id
#      p selected
#    end
#  end

end
