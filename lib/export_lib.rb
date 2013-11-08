#### NEED TO REMOVE ALL NAMED ARGUMENTS. DOESN'T WORK


# encoding: UTF-8

require 'fileutils'

class Exporter  #{{{1

  def initialize(p_id, ef_id, is_diagnostic)  #{{{2
    @EXPORT_PATH     = './output/'
    @filepath_lookup = Hash.new
    @p_id            = p_id
    @ef_id           = ef_id
    @lof_errors      = Array.new
    @common_info     = Hash.new

    FileUtils.mkpath @EXPORT_PATH unless File.exists? @EXPORT_PATH

    # Build a list of sections. Each section will have its own csv file
    @sections = [:KeyQuestion, :Publication, :DesignDetail]
    if is_diagnostic
      @sections.concat([:DiagnosticTest, :DiagnosticTestDetail])
    else
      @sections.concat([:Arm, :ArmDetail])
    end
    @sections.concat([:BaselineCharacteristic, :Outcome, :OutcomeDetail,
                      :AdverseEvent, :QualityDimension, :QualityRating])
  end

  def get_project_id  #{{{2
    @p_id
  end

  def get_extraction_form_id  #{{{2
    @ef_id
  end

  def build_arm_csv  #{{{2
  end

  def build_outcome_csv  #{{{2
  end

  def build_details_csv  #{{{2
  end

  # We get the list of study ids by their association to the extraction form
  # This can be found in the study_extraction_forms table
  def get_lof_study_ids  #{{{2
    lof_study_ids = []
    sefs = StudyExtractionForm.find(:all, :conditions => { :extraction_form_id => @ef_id })
    sefs.each do |s|
      lof_study_ids.push s.study_id
    end
    return lof_study_ids
  end

  def export  #{{{2
    lof_study_ids = get_lof_study_ids
    if lof_study_ids.blank?
      @lof_errors.push "Skipping extraction form id #{@ef_id}. No associated studies found."
    else
      errors = _build_export(lof_study_ids)
      @lof_errors.concat errors
    end
  end

  def log_errors  #{{{2
    unless @lof_errors.blank?
      puts " ++++++++++ EF ID #{@ef_id} ERRORS ++++++++++"
      puts "  ++++++++++++++++++++++++++++++++++++++++++++"
      @lof_errors.each do |e|
        #!!! Write these to a log file instead by extraction form id
        puts e
      end
    end
  end

  def _build_export(lof_study_ids)  #{{{2
    errors = []

    # We skip checking QualityRatings section because it is part of the QualityDimensions section
    sections = @sections - [:QualityRating]

    sections.each do |s|

      # Check if section is to be processed.
      efs = ExtractionFormSection.find(:first, :conditions => { :extraction_form_id => @ef_id,
                                                                :section_name => short_section_name[s] })
      if efs.blank?
        errors << "  Unable to find extraction form section entry for study id #{id}, section name #{s}"
      else
        if efs.included
          puts "working on section #{s}"

          # Prepare csv file for this section
          prep_csv(:section => s)

          lof_study_ids.each do |id|
            puts "  working on study id #{id}"

            _process_section({ :study_id => id, :section => s })

            # Since we made QualityRatings dependent on the QualityDimensions section,
            # we need to process QualityRatings section if QualityDimensions are included
            if s==:QualityDimension

              # Prepare csv file for this section
              prep_csv(:section => :QualityRating )

              _process_section({ :study_id => id, :section => :QualityRating })
            end
          end
        elsif s==:KeyQuestion || s==:Publication
          puts "working on section #{s}"

          # Prepare csv file for this section
          prep_csv(:section => s)

          lof_study_ids.each do |id|
            puts "  working on study id #{id}"
            # KeyQuestions and Publications sections are set to false in the included cell
            # by default. So we include them regardless of the .included check.
            _process_section({ :study_id => id, :section => s })
          end
        else
          errors << "  INFO: Section #{s} is not included on extraction form #{@ef_id}"
        end
      end
    end

    return errors
  end

  def _process_section(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]

    case section
    when :KeyQuestion
      _process_key_questions({ :study_id => study_id, :section => section })
    when :Publication
      _process_publications({ :study_id => study_id, :section => section })
    when :DesignDetail
      _process_section_details({ :study_id => study_id, :section => section })
    when :DiagnosticTest
      lof_diagnostic_tests = _get_lof_diagnostic_tests(study_id)
      lof_suggested_diagnostic_tests = _get_lof_suggested_diagnostic_tests

      _process_diagnostic_tests({ :study_id => study_id,
                                  :section => section,
                                  :diagnostic_tests => lof_diagnostic_tests,
                                  :suggested_diagnostic_tests => lof_suggested_diagnostic_tests })
    when :DiagnosticTestDetail
      #!!!
      section_option = _get_section_option("diagnostic_test_detail")
      if section_option.by_diagnostic_test
        lof_diagnostic_tests = _get_lof_diagnostic_tests(study_id)
        lof_diagnostic_tests.each do |dt|
          _process_diagnostic_test_details({ :study_id => study_id, :section => section, :diagnostic_test_id => dt.id })
        end
      else
        _process_diagnostic_test_details({ :study_id => study_id, :section => section, :diagnostic_test_id => 0 })
      end
    when :Arm
      _process_arms({ :study_id => study_id, :section => section })
    when :ArmDetail
      section_option = _get_section_option("arm_detail")
      if section_option.by_arm
        lof_arms = _get_lof_arms(study_id)
        lof_arms.each do |a|
          _process_section_details({ :study_id => study_id, :section => section, :arm_id => a.id })
        end
      else
        _process_section_details({ :study_id => study_id, :section => section, :arm_id => 0 })
      end
    when :BaselineCharacteristic
      lof_arms = _get_lof_arms(study_id)
      lof_arm_ids = lof_arms.collect { |a| a.id }
      lof_arm_ids << 0  # This is for the "All Arms (Total)" arm.
      lof_arm_ids.each do |id|
        _process_section_details({ :study_id => study_id, :section => section, :arm_id => id })
      end
    when :Outcome
      lof_outcomes              = _get_lof_outcomes(study_id)
      lof_suggested_outcomes    = _get_lof_suggested_outcomes

      _process_outcomes({ :study_id           => study_id,
                          :section            => section,
                          :outcomes           => lof_outcomes,
                          :suggested_outcomes => lof_suggested_outcomes })
    when :OutcomeDetail
      section_option = _get_section_option("outcome_detail")
      if section_option.by_outcome
        lof_outcomes = _get_lof_outcomes(study_id)
        lof_outcomes.each do |o|
          _process_section_details({ :study_id => study_id, :section => section, :outcome_id => o.id })
        end
      else
        _process_section_details({ :study_id => study_id, :section => section, :outcome_id => 0 })
      end
    when :AdverseEvent
      lof_arms                     = _get_lof_arms(study_id)
      lof_suggested_adverse_events = _get_lof_suggested_adverse_events
      lof_adverse_events           = _get_lof_adverse_events(study_id)
      lof_adverse_event_columns    = _get_lof_adverse_event_columns

      _process_adverse_events({ :study_id                 => study_id,
                                :section                  => section,
                                :arms                     => lof_arms,
                                :suggested_adverse_events => lof_suggested_adverse_events,
                                :adverse_events           => lof_adverse_events,
                                :adverse_event_columns    => lof_adverse_event_columns })
    when :QualityDimension
      lof_quality_dimension_fields = _get_lof_quality_dimension_fields
      lof_quality_dimension_fields.each do |qdf|
        _process_quality_dimension({ :study_id                => study_id,
                                     :section                 => section,
                                     :quality_dimension_field => qdf })
      end
    when :QualityRating
      lof_quality_rating_fields = _get_lof_quality_rating_fields
      lof_quality_rating_fields.each do |qrf|
        _process_quality_rating({ :study_id             => study_id,
                                  :section              => section,
                                  :quality_rating_field => qrf })
      end
    else
      @lof_errors << "Failure to sort section #{section} for study ID #{study_id} extraction form ID #{@ef_id}"
    end
  end

  def _process_diagnostic_tests(params)  #{{{2
    test_type_lookup = { 1 => 'Index Text', 2 => 'Reference Test' }

    study_id = params[:study_id]
    section = params[:section]
    diagnostic_tests = params[:diagnostic_tests]
    suggested_diagnostic_tests = params[:suggested_diagnostic_tests]

    diagnostic_test_titles = diagnostic_tests.collect { |test| test.title }
    suggested_diagnostic_test_titles = suggested_diagnostic_tests.collect { |suggested_test| suggested_test.title }

    diagnostic_tests.each do |dt|
      dt_title       = dt.title
      dt_type        = test_type_lookup[dt.test_type]
      dt_description = dt.description
      dt_notes       = dt.notes
      selected       = "Y"
      if suggested_diagnostic_test_titles.include? dt.title
        is_suggested = "Y"
      else
        is_suggested = ""
      end

      lof_diagnostic_test_thresholds = _get_lof_diagnostic_test_thresholds(dt.id)
      lof_diagnostic_test_thresholds.each do |dtt|
        dt_threshold = dtt.threshold
        data = [dt_title,
                dt_type,
                dt_description,
                dt_notes,
                selected,
                is_suggested,
                dt_threshold
               ]
        _write_to_csv(study_id, section, data)
      end
    end

    suggested_diagnostic_tests.each do |sdt|
      unless diagnostic_test_titles.include? sdt.title
        dt_title = sdt.title
        dt_type = test_type_lookup[sdt.test_type]
        dt_description = sdt.description
        dt_notes = sdt.notes
        selected = ""
        is_suggested = "Y"
        dt_threshold = ""

        data = [dt_title,
                dt_type,
                dt_description,
                dt_notes,
                selected,
                is_suggested,
                dt_threshold
               ]
        _write_to_csv(study_id, section, data)
      end
    end
  end

  def _get_lof_diagnostic_test_thresholds(diagnostic_test_id)  #{{{2
    DiagnosticTestThreshold.find(:all, :conditions => { :diagnostic_test_id => diagnostic_test_id })
  end

  def _get_lof_diagnostic_tests(study_id)  #{{{2
    DiagnosticTest.find(:all, :conditions => { :study_id => study_id,
                                               :extraction_form_id => @ef_id })
  end

  def _get_lof_suggested_diagnostic_tests  #{{{2
    ExtractionFormDiagnosticTest.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _process_outcomes(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    outcomes = params[:outcomes]
    suggested_outcomes = params[:suggested_outcomes]

    outcome_titles = outcomes.collect { |outcome| outcome.title }
    suggested_outcome_titles = suggested_outcomes.collect { |suggested_outcome| suggested_outcome.title }

    outcomes.each do |outcome|
      outcome_id = outcome.id
      outcome_title = outcome.title
      outcome_description = outcome.description
      outcome_type = outcome.outcome_type
      outcome_selected = "Y"
      population_selected = "Y"
      timepoint_selected = "Y"

      if suggested_outcome_titles.include? outcome_title
        outcome_suggested_by_lead = "Y"
      else
        outcome_suggested_by_lead = ""
      end

      populations = _get_outcome_populations(outcome.id)
      timepoints = _get_outcome_timepoints(outcome.id)

      populations.each do |p|
        population_id = p.id
        population_title = p.title
        population_description = p.description

        timepoints.each do |t|
          timepoint_id = t.id
          timepoint_title = t.number.strip
          timepoint_unit = t.time_unit.strip

          data = [outcome_title,
                  outcome_description,
                  outcome_type,
                  outcome_selected,
                  outcome_suggested_by_lead,
                  population_title,
                  population_selected,
                  population_description,
                  timepoint_title,
                  timepoint_unit,
                  timepoint_selected,
                  outcome_id,
                  population_id,
                  timepoint_id]
          _write_to_csv(study_id, section, data)
        end
      end
    end

    suggested_outcomes.each do |so|
      unless outcome_titles.include? so.title
        outcome_title = so.title
        outcome_selected = ""
        outcome_suggested_by_lead = "Y"
        outcome_description = so.note
        outcome_type = so.outcome_type
        population_title = "All Participants"
        population_selected = ""
        population_description = "All participants involved in the study (Default)"
        timepoint_title = ""
        timepoint_unit = ""
        timepoint_selected = ""
        outcome_id = ""
        population_id = ""
        timepoint_id = ""
        
        data = [outcome_title,
                outcome_description,
                outcome_type,
                outcome_selected,
                outcome_suggested_by_lead,
                population_title,
                population_selected,
                population_description,
                timepoint_title,
                timepoint_unit,
                timepoint_selected,
                outcome_id,
                population_id,
                timepoint_id]
        _write_to_csv(study_id, section, data)
      end
    end
  end

  def _get_lof_suggested_outcomes  #{{{2
    ExtractionFormOutcomeName.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _get_outcome_populations(outcome_id)  #{{{2
    OutcomeSubgroup.find(:all, :conditions => { :outcome_id => outcome_id })
  end

  def _get_outcome_timepoints(outcome_id)  #{{{2
    OutcomeTimepoint.find(:all, :conditions => { :outcome_id => outcome_id })
  end

  def _process_quality_rating(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    quality_rating_field = params[:quality_rating_field]

    qrdp = QualityRatingDataPoint.find(:first,
            :conditions => { :study_id           => study_id,
                             :extraction_form_id => @ef_id })

    if qrdp.blank?
      quality_guideline_used = ""
      current_overall_rating = quality_rating_field.rating_item
      selected = ""
      notes = ""
    else
      if qrdp.current_overall_rating.strip==quality_rating_field.rating_item.strip
        quality_guideline_used = qrdp.guideline_used.strip
        current_overall_rating = quality_rating_field.rating_item.strip
        selected = "Y"
        notes = qrdp.notes.strip
      else
        quality_guideline_used = qrdp.guideline_used.strip
        current_overall_rating = quality_rating_field.rating_item.strip
        selected = ""
        notes = qrdp.notes.strip
      end
    end

    data = [quality_guideline_used, current_overall_rating, selected, notes]
    _write_to_csv(study_id, section, data)
  end

  def _process_quality_dimension(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    quality_dimension_field = params[:quality_dimension_field]

    qddp = QualityDimensionDataPoint.find(:first,
            :conditions => { :quality_dimension_field_id => quality_dimension_field,
                             :study_id                   => study_id,
                             :extraction_form_id         => @ef_id })
    if qddp.blank?
      qddp_value = ""
      selected = ""
      notes = ""
      instructions = quality_dimension_field.field_notes.blank? ? "" : quality_dimension_field.field_notes.strip
    else
      qddp_value = qddp.value.strip
      selected = "Y"
      notes = qddp.notes.blank? ? "" : qddp.notes.strip
      instructions = quality_dimension_field.field_notes.blank? ? "" : quality_dimension_field.field_notes.strip
    end

    data = [quality_dimension_field.title, qddp_value, selected, notes, instructions]
    _write_to_csv(study_id, section, data)
  end

  def _get_lof_quality_rating_fields  #{{{2
    QualityRatingField.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _get_lof_quality_dimension_fields  #{{{2
    QualityDimensionField.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _get_lof_suggested_adverse_events  #{{{2
    ExtractionFormAdverseEvent.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _get_lof_adverse_events(study_id)  #{{{2
    ae = AdverseEvent.find(:all, :conditions => { :study_id           => study_id,
                                                  :extraction_form_id => @ef_id })
    if ae.blank?
      ae = AdverseEvent.create(:study_id           => study_id,
                               :extraction_form_id => @ef_id)
      return [ae]
    end

    return ae
  end

  def _get_lof_adverse_event_columns  #{{{2
    AdverseEventColumn.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _process_adverse_events(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    arms = params[:arms]
    suggested_adverse_events = params[:suggested_adverse_events]
    adverse_events = params[:adverse_events]
    adverse_event_columns = params[:adverse_event_columns]

    ef = ExtractionForm.find(@ef_id)
    display_by_arms = ef.adverse_event_display_arms
    display_by_total = ef.adverse_event_display_total

    adverse_events.each do |ae|
      adverse_event_columns.each do |aec|
        if display_by_arms
          arms.each do |a|
            aer = AdverseEventResult.find(:first, :conditions => { :column_id        => aec.id,
                                                                   :adverse_event_id => ae.id,
                                                                   :arm_id           => a.id })
            if aer.blank?
              ae_selected  = ""
              aer_value    = ""
              aer_selected = ""
              aer_id       = ""
            else
              ae_selected  = "Y"
              aer_value    = aer.value
              aer_selected = "Y"
              aer_id       = aer.id
            end
            data = [a.title, ae.title, ae_selected, ae.description, aec.name, aer_value, aer_selected, aer_id]
            _write_to_csv(study_id, section, data)
          end
        end
        if display_by_total
          aer = AdverseEventResult.find(:first, :conditions => { :column_id        => aec.id,
                                                                 :adverse_event_id => ae.id,
                                                                 :arm_id           => -1 })
          if aer.blank?
            ae_selected  = ""
            aer_value    = ""
            aer_selected = ""
            aer_id       = ""
          else
            ae_selected  = "Y"
            aer_value    = aer.value
            aer_selected = "Y"
            aer_id       = aer.id
          end
          data = ['Total', ae.title, ae_selected, ae.description, aec.name, aer_value, aer_selected, aer_id]
            _write_to_csv(study_id, section, data)
        end
      end
    end

    # Now add rows for the suggested adverse events that were not used
    suggested_adverse_events.each do |sae|
      suggestion_found = false
      adverse_events.each do |ae|
        suggestion_found = true if ae.title==sae.title
      end

      unless suggestion_found
        adverse_event_columns.each do |aec|
          if display_by_arms
            arms.each do |a|
              ae_title       = sae.title
              ae_selected    = ""
              ae_description = ""
              aer_value      = ""
              aer_selected   = ""
              aer_id         = ""

              data = [a.title, ae_title, ae_selected, ae_description, aec.name, aer_value, aer_selected, aer_id]
              _write_to_csv(study_id, section, data)
            end
          end
          if display_by_total
            ae_title       = sae.title
            ae_selected    = ""
            ae_description = ""
            aer_value      = ""
            aer_selected   = ""
            aer_id         = ""

            data = ['Total', ae_title, ae_selected, ae_description, aec.name, aer_value, aer_selected, aer_id]
              _write_to_csv(study_id, section, data)
          end
        end
      end
    end
  end

  def _get_lof_outcomes(study_id)  #{{{2
    Outcome.find(:all, :conditions => { study_id: study_id })
  end

  def _get_section_option(section)  #{{{2
    EfSectionOption.find(:first, :conditions => { :extraction_form_id => @ef_id,
                                                  :section            => section })
  end

  def _process_key_questions(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]

    lof_kq_ids = _get_lof_kq_ids(study_id=study_id)
    lof_kqs = KeyQuestion.find(:all, :conditions => ["id in (?)", lof_kq_ids])
    lof_kqs.each do |kq|
      kq_data = [kq.id, kq.question_number, kq.question]
      _write_to_csv(study_id, section, kq_data)
    end
  end

  def _process_publications(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]

    data = []
    _write_to_csv(study_id, section, data)
  end

  def _process_diagnostic_test_details(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    diagnostic_test_id = params[:diagnostic_test_id]

    lof_diagnostic_test_details = _get_lof_diagnostic_test_details(section)
    lof_diagnostic_test_details.each do |dtd|
      _diagnostic_test_detail_info({ :study_id => study_id,
                                     :diagnostic_test_id => diagnostic_test_id,
                                     :section => section,
                                     :diagnostic_test_detail => dtd })
    end
  end

  def _get_lof_diagnostic_test_details(section)  #{{{2
    "#{section.to_s}".constantize.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def _process_section_details(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]

    lof_section_details = _get_lof_section_details(section)
    lof_section_details.each do |sd|
      _section_detail_info({ :study_id => study_id,
                             :arm_id => arm_id,
                             :outcome_id => outcome_id,
                             :section => section,
                             :section_detail => sd })
    end
  end

  def _process_arms(params)  #{{{2
    study_id = params[:study_id]
    section = params[:section]

    lof_arms = _get_lof_arms(study_id)
    lof_arms_suggested_by_project_lead = _get_lof_arms_suggested_by_project_lead()

    lof_arm_titles_suggested = lof_arms_suggested_by_project_lead.collect { |a| a.name }

    lof_arms.each do |a|
      if lof_arm_titles_suggested.delete a.title
        selected = "Y"
        is_suggested_by_lead = "Y"
      else
        selected = "Y"
        is_suggested_by_lead = ""
      end
      data = [a.title, selected, is_suggested_by_lead]
      _write_to_csv(study_id, section, data)
    end

    lof_arm_titles_suggested.each do |arm_suggested|
      selected = ""
      is_suggested_by_lead = "Y"
      data = [arm_suggested, selected, is_suggested_by_lead]
      
      _write_to_csv(study_id, section, data)
    end
  end

  def _get_lof_arms_suggested_by_project_lead()  #{{{2
    ExtractionFormArm.find(:all,
            :conditions => { :extraction_form_id => @ef_id })
  end

  def _get_lof_arms(study_id)  #{{{2
    Arm.find(:all, :conditions => { :study_id => study_id,
                                    :extraction_form_id => @ef_id })
  end

  def _get_lof_kq_ids(study_id)  #{{{2
    lof_kq_ids = Array.new

    study_key_questions = StudyKeyQuestion.find_all_by_study_id(study_id)
    study_key_questions.each do |s|
      lof_kq_ids << s.key_question_id
    end
    return lof_kq_ids
  end

  def _cache_common_info_for_study(study_id, section)  #{{{2
    common_info_study_section = Hash.new
    pp = PrimaryPublication.find(:first, :conditions => { :study_id => study_id })

    common_info_study_section[:project_id] = @p_id
    common_info_study_section[:project_title] = Project.find(@p_id).title
    common_info_study_section[:ef_title] = ExtractionForm.find(@ef_id).title
    common_info_study_section[:section] = section.to_s
    common_info_study_section[:study_id] = study_id

    if pp.blank?
      @lof_errors << "Unable to find PrimaryPublication data for study id #{study_id}"
    else
      ppn = PrimaryPublicationNumber.find(:first, :conditions => { :primary_publication_id => pp.id })

      if ppn.blank?
        @lof_errors << "Unable to find PrimaryPublicationNumber data for study id #{study_id}"
        ppn = PrimaryPublicationNumber.new(:number => "", :number_type => "")
      end

      common_info_study_section[:pp_title] = pp.title
      common_info_study_section[:pp_author] = pp.author
      common_info_study_section[:pp_country] = pp.country
      common_info_study_section[:pp_year] = pp.year
      common_info_study_section[:pp_pmid] = pp.pmid
      common_info_study_section[:pp_journal] = pp.journal
      common_info_study_section[:pp_volume] = pp.volume
      common_info_study_section[:pp_issue] = pp.issue
      common_info_study_section[:pp_trial_title] = pp.trial_title
      common_info_study_section[:ppn_identifier_type] = ppn.number_type
      common_info_study_section[:ppn_identifier] = ppn.number
    end

    @common_info[study_id][section] = common_info_study_section
  end

  def _write_to_csv(study_id, section, data)  #{{{2
    @common_info[study_id] = Hash.new if @common_info[study_id].blank?
    _cache_common_info_for_study(study_id, section) if @common_info[study_id][section].blank?

    CSV.open(@filepath_lookup[section], 'a') do |csv|
      csv << [@common_info[study_id][section][:project_id],
              @common_info[study_id][section][:project_title],
              @common_info[study_id][section][:ef_title],
              @common_info[study_id][section][:section],
              @common_info[study_id][section][:pp_author],
              @common_info[study_id][section][:pp_title],
              @common_info[study_id][section][:pp_country],
              @common_info[study_id][section][:pp_year],
              @common_info[study_id][section][:pp_journal],
              @common_info[study_id][section][:pp_volume],
              @common_info[study_id][section][:pp_issue],
              @common_info[study_id][section][:pp_trial_title],
              @common_info[study_id][section][:ppn_identifier_type],
              @common_info[study_id][section][:ppn_identifier],
              @common_info[study_id][section][:pp_pmid],
              @common_info[study_id][section][:study_id],
             ] + data
    end
  end

  def _diagnostic_test_detail_info(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:diagnostic_test_detail]

    case section_detail.field_type
    when /text/
      _text_question_dt({ :study_id => study_id,
                          :diagnostic_test_id => diagnostic_test_id,
                          :section => section,
                          :section_detail => section_detail })
    when /matrix_radio/
      _matrix_radio_question_dt({ :study_id => study_id,
                                  :diagnostic_test_id => diagnostic_test_id,
                                  :section => section,
                                  :section_detail => section_detail })
    when /matrix_checkbox/
      _matrix_checkbox_question_dt({ :study_id => study_id,
                                     :diagnostic_test_id => diagnostic_test_id,
                                     :section => section,
                                     :section_detail => section_detail })
    when /matrix_select/
      _matrix_select_question_dt({ :study_id => study_id,
                                   :diagnostic_test_id => diagnostic_test_id,
                                   :section => section,
                                   :section_detail => section_detail })
    else # select, radio, checkbox
      _single_column_answer_question_dt({ :study_id => study_id,
                                          :diagnostic_test_id => diagnostic_test_id,
                                          :section => section,
                                          :section_detail => section_detail })
    end
  end

  def _section_detail_info(params)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    case section_detail.field_type
    when /text/
      _text_question({ :study_id => study_id,
                       :arm_id => arm_id,
                       :outcome_id => outcome_id,
                       :section => section,
                       :section_detail => section_detail })
    when /matrix_radio/
      _matrix_radio_question({ :study_id => study_id,
                               :arm_id => arm_id,
                               :outcome_id => outcome_id,
                               :section => section,
                               :section_detail => section_detail })
    when /matrix_checkbox/
      _matrix_checkbox_question({ :study_id => study_id,
                                  :arm_id => arm_id,
                                  :outcome_id => outcome_id,
                                  :section => section,
                                  :section_detail => section_detail })
    when /matrix_select/
      _matrix_select_question({ :study_id => study_id,
                                :arm_id => arm_id,
                                :outcome_id => outcome_id,
                                :section => section,
                                :section_detail => section_detail })
    else # select, radio, checkbox
      _single_column_answer_question({ :study_id => study_id,
                                       :arm_id => arm_id,
                                       :outcome_id => outcome_id,
                                       :section => section,
                                       :section_detail => section_detail })
    end
  end

  def _matrix_radio_question(params)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })

    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :arm_id                                      => arm_id,
                                 :outcome_id                                  => outcome_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :arm_id                                      => arm_id,
                                                            :outcome_id                                  => outcome_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array({ :section => section,
                                   :section_detail => section_detail,
                                   :arm_id => arm_id,
                                   :outcome_id => outcome_id,
                                   :sddp => sddp,
                                   :sddp_id => sddp_id,
                                   :row => r,
                                   :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                  :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                   :value                                       => c.option_text,
                                   :study_id                                    => study_id,
                                   :extraction_form_id                          => @ef_id,
                                   :row_field_id                                => r.id,
                                   :arm_id                                      => arm_id,
                                   :outcome_id                                  => outcome_id })
          if sddp.blank?
            sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                              :value                                       => c.option_text,
                                                              :study_id                                    => study_id,
                                                              :extraction_form_id                          => @ef_id,
                                                              :row_field_id                                => r.id,
                                                              :column_field_id                             => 0,
                                                              :arm_id                                      => arm_id,
                                                              :outcome_id                                  => outcome_id)
            sddp_id = ""
            selected = ""
          else
            sddp_id = sddp.id
            selected = sddp.value.blank? ? "" : "Y"
          end

          data = _build_data_array({ :section => section,
                                     :section_detail => section_detail,
                                     :arm_id => arm_id,
                                     :outcome_id => outcome_id,
                                     :sddp => sddp,
                                     :sddp_id => sddp_id,
                                     :row => r,
                                     :col => c,
                                     :selected => selected })
          _write_to_csv(study_id, section, data)
        end
      end
    end
  end

  def _matrix_radio_question_dt(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })

    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :diagnostic_test_id                          => diagnostic_test_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :diagnostic_test_id                          => diagnostic_test_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array_dt({ :section => section,
                                      :section_detail => section_detail,
                                      :diagnostic_test_id => diagnostic_test_id,
                                      :sddp => sddp,
                                      :sddp_id => sddp_id,
                                      :row => r,
                                      :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                  :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                   :value                                       => c.option_text,
                                   :study_id                                    => study_id,
                                   :extraction_form_id                          => @ef_id,
                                   :row_field_id                                => r.id,
                                   :diagnostic_test_id                          => diagnostic_test_id })
          if sddp.blank?
            sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                              :value                                       => c.option_text,
                                                              :study_id                                    => study_id,
                                                              :extraction_form_id                          => @ef_id,
                                                              :row_field_id                                => r.id,
                                                              :column_field_id                             => 0,
                                                              :diagnostic_test_id                          => diagnostic_test_id)
            sddp_id = ""
            selected = ""
          else
            sddp_id = sddp.id
            selected = sddp.value.blank? ? "" : "Y"
          end

          data = _build_data_array_dt({ :section => section,
                                        :section_detail => section_detail,
                                        :diagnostic_test_id => diagnostic_test_id,
                                        :sddp => sddp,
                                        :sddp_id => sddp_id,
                                        :row => r,
                                        :col => c,
                                        :selected => selected })
          _write_to_csv(study_id, section, data)
        end
      end
    end
  end

  def _build_data_array(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    sddp = params[:sddp]
    sddp_id = params[:sddp_id].blank? ? "" : params[:sddp_id]
    row = params[:row]
    col = params[:col]
    selected = params[:selected]

    question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip
  
    arm = Arm.find(:first, :conditions => { :id => arm_id })
    if section==:BaselineCharacteristic && arm_id==0
      arm_title = "All Arms (Total)"
    else
      arm_title = arm.blank? ? "" : arm.title.strip
    end
  
    outcome = Outcome.find(:first, :conditions => { :id => outcome_id })
    outcome_title = outcome.blank? ? "" : outcome.title.strip
  
    question = section_detail.question.blank? ? "" : section_detail.question.strip
    row_option_text = row.option_text.blank? ? "" : row.option_text.strip unless row.nil?
    col_option_text = col.option_text.blank? ? "" : col.option_text.strip unless col.nil?
    value = sddp.value.blank? ? "" : sddp.value.strip
    notes = sddp.notes.blank? ? "" : sddp.notes.strip
    subquestion = row.subquestion.blank? ? "" : row.subquestion.strip
    subquestion_value = sddp.subquestion_value.blank? ? "" : sddp.subquestion_value.strip
  
    [question_type,
     arm_title,
     outcome_title,
     question,
     row_option_text,
     col_option_text,
     value,
     selected,
     notes,
     subquestion,
     subquestion_value,
     sddp_id]
  end

  def _build_data_array_dt(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    diagnostic_test_id = params[:diagnostic_test_id]
    sddp = params[:sddp]
    sddp_id = params[:sddp_id].blank? ? "" : params[:sddp_id]
    row = params[:row]
    col = params[:col]
    selected = params[:selected]

    question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip
  
    diagnostic_test = DiagnosticTest.find(:first, :conditions => { :id => diagnostic_test_id })
    diagnostic_test_title = diagnostic_test.blank? ? "" : diagnostic_test.title.strip
  
    question = section_detail.question.blank? ? "" : section_detail.question.strip
    row_option_text = row.option_text.blank? ? "" : row.option_text.strip unless row.nil?
    col_option_text = col.option_text.blank? ? "" : col.option_text.strip unless col.nil?
    value = sddp.value.blank? ? "" : sddp.value.strip
    notes = sddp.notes.blank? ? "" : sddp.notes.strip
    subquestion = row.subquestion.blank? ? "" : row.subquestion.strip
    subquestion_value = sddp.subquestion_value.blank? ? "" : sddp.subquestion_value.strip
  
    [question_type,
     diagnostic_test_title,
     question,
     row_option_text,
     col_option_text,
     value,
     selected,
     notes,
     subquestion,
     subquestion_value,
     sddp_id]
  end

  def _matrix_checkbox_question(params)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })
    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :arm_id                                      => arm_id,
                                 :outcome_id                                  => outcome_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :arm_id                                      => arm_id,
                                                            :outcome_id                                  => outcome_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array({ :section => section,
                                   :section_detail => section_detail,
                                   :arm_id => arm_id,
                                   :outcome_id => outcome_id,
                                   :sddp => sddp,
                                   :sddp_id => sddp_id,
                                   :row => r,
                                   :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          sddp, sddp_id, selected = _find_matrix_checkbox_sddp({section: section, section_detail: section_detail,
                                            study_id: study_id, row_field: r, col_field: c, arm_id: arm_id,
                                            outcome_id: outcome_id })
          data = _build_data_array({ :section => section,
                                     :section_detail => section_detail,
                                     :arm_id => arm_id,
                                     :outcome_id => outcome_id,
                                     :sddp => sddp,
                                     :sddp_id => sddp_id,
                                     :row => r,
                                     :col => c,
                                     :selected => selected })
          _write_to_csv(study_id, section, data)
        end
      end
    end
  end

  def _matrix_checkbox_question_dt(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })
    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :diagnostic_test_id                          => diagnostic_test_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :diagnostic_test_id                          => diagnostic_test_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array_dt({ :section => section,
                                      :section_detail => section_detail,
                                      :diagnostic_test_id => diagnostic_test_id,
                                      :sddp => sddp,
                                      :sddp_id => sddp_id,
                                      :row => r,
                                      :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          sddp, sddp_id, selected = _find_matrix_checkbox_sddp_dt({section: section, section_detail: section_detail,
                                            study_id: study_id, row_field: r, col_field: c, diagnostic_test_id: diagnostic_test_id })
          data = _build_data_array_dt({ :section => section,
                                        :section_detail => section_detail,
                                        :diagnostic_test_id => diagnostic_test_id,
                                        :sddp => sddp,
                                        :sddp_id => sddp_id,
                                        :row => r,
                                        :col => c,
                                        :selected => selected })
          _write_to_csv(study_id, section, data)
        end
      end
    end
  end

  def _find_matrix_checkbox_sddp(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    study_id = params[:study_id]
    row_field = params[:row_field].blank? ? 0 : params[:row_field]
    col_field = params[:col_field].blank? ? 0 : params[:col_field]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]

    sddp = "#{section.to_s}DataPoint".constantize.find(:first,
            :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                             :value                                       => col_field.option_text,
                             :study_id                                    => study_id,
                             :extraction_form_id                          => @ef_id,
                             :row_field_id                                => row_field.id,
                             :column_field_id                             => 0,
                             :arm_id                                      => arm_id,
                             :outcome_id                                  => outcome_id })
    if sddp.blank?
      sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                        :value                                       => col_field.option_text,
                                                        :study_id                                    => study_id,
                                                        :extraction_form_id                          => @ef_id,
                                                        :row_field_id                                => row_field.id,
                                                        :column_field_id                             => 0,
                                                        :arm_id                                      => arm_id,
                                                        :outcome_id                                  => outcome_id)
      sddp_id = ""
      selected = ""
    else
      sddp_id = sddp.id
      selected = "Y"
    end

    return sddp, sddp_id, selected
  end

  def _find_matrix_checkbox_sddp_dt(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    study_id = params[:study_id]
    row_field = params[:row_field].blank? ? 0 : params[:row_field]
    col_field = params[:col_field].blank? ? 0 : params[:col_field]
    diagnostic_test_id = params[:diagnostic_test_id]

    sddp = "#{section.to_s}DataPoint".constantize.find(:first,
            :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                             :value                                       => col_field.option_text,
                             :study_id                                    => study_id,
                             :extraction_form_id                          => @ef_id,
                             :row_field_id                                => row_field.id,
                             :column_field_id                             => 0,
                             :diagnostic_test_id                          => diagnostic_test_id })
    if sddp.blank?
      sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                        :value                                       => col_field.option_text,
                                                        :study_id                                    => study_id,
                                                        :extraction_form_id                          => @ef_id,
                                                        :row_field_id                                => row_field.id,
                                                        :column_field_id                             => 0,
                                                        :diagnostic_test_id                          => diagnostic_test_id)
      sddp_id = ""
      selected = ""
    else
      sddp_id = sddp.id
      selected = "Y"
    end

    return sddp, sddp_id, selected
  end

  def _matrix_select_question(params) #(study_id, arm_id, outcome_id, section, section_detail)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })

    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :arm_id                                      => arm_id,
                                 :outcome_id                                  => outcome_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :arm_id                                      => arm_id,
                                                            :outcome_id                                  => outcome_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array({ :section => section,
                                   :section_detail => section_detail,
                                   :arm_id => arm_id,
                                   :outcome_id => outcome_id,
                                   :sddp => sddp,
                                   :sddp_id => sddp_id,
                                   :row => r,
                                   :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          lof_matrix_dropdown_option_values = _get_lof_matrix_dropdown_option_values({ section: section.to_s, row_id: r.id, col_id: c.id })
          if lof_matrix_dropdown_option_values.length>0
            if section_detail.include_other_as_option
              lof_matrix_dropdown_option_values.push "Other..." 
            end

            # do this the other way around. Find all the answer that are already in the system and compare to 
            # options that were given. remove it from the array once we print one out.
            lof_matrix_dropdown_option_values.each do |v|
              sddp, sddp_id, selected = _find_matrix_select_sddp({section: section, section_detail: section_detail, study_id: study_id,
                                                    row_field: r, col_field: c, arm_id: arm_id, outcome_id: outcome_id,
                                                    value: v, lof_matrix_dropdown_option_values: lof_matrix_dropdown_option_values })
              data = _build_data_array({ :section => section,
                                         :section_detail => section_detail,
                                         :arm_id => arm_id,
                                         :outcome_id => outcome_id,
                                         :sddp => sddp,
                                         :sddp_id => sddp_id,
                                         :row => r,
                                         :col => c,
                                         :selected => selected })
              _write_to_csv(study_id, section, data)
            end

          # This must be a text box
          else
            sddp, sddp_id, selected = _find_matrix_select_sddp({section: section, section_detail: section_detail, study_id: study_id,
                                                  row_field: r, col_field: c, arm_id: arm_id, outcome_id: outcome_id,
                                                  value: nil })
            data = _build_data_array({ :section => section,
                                       :section_detail => section_detail,
                                       :arm_id => arm_id,
                                       :outcome_id => outcome_id,
                                       :sddp => sddp,
                                       :sddp_id => sddp_id,
                                       :row => r,
                                       :col => c,
                                       :selected => selected })
            _write_to_csv(study_id, section, data)
          end
        end
      end
    end
  end

  def _matrix_select_question_dt(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:section_detail]

    rows = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :column_number                         => 0 })
    cols = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id,
                             :row_number                            => 0 })

    rows.each do |r|
      # row_number of -1 means this is an "Other (please specify)" option
      if r.row_number==-1
        sddp = "#{section.to_s}DataPoint".constantize.find(:first,
                :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                 :study_id                                    => study_id,
                                 :extraction_form_id                          => @ef_id,
                                 :diagnostic_test_id                          => diagnostic_test_id,
                                 :row_field_id                                => r.id })
        if sddp.blank?
          sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                            :study_id                                    => study_id,
                                                            :extraction_form_id                          => @ef_id,
                                                            :row_field_id                                => r.id,
                                                            :column_field_id                             => 0,
                                                            :diagnostic_test_id                          => diagnostic_test_id)
          sddp_id = ""
          selected = ""
        else
          sddp_id = sddp.id
          selected = sddp.value.blank? ? "" : "Y"
        end
  
        data = _build_data_array_dt({ :section => section,
                                      :section_detail => section_detail,
                                      :diagnostic_test_id => diagnostic_test_id,
                                      :sddp => sddp,
                                      :sddp_id => sddp_id,
                                      :row => r,
                                      :selected => selected })
        _write_to_csv(study_id, section, data)
      else
        cols.each do |c|
          lof_matrix_dropdown_option_values = _get_lof_matrix_dropdown_option_values({ section: section.to_s, row_id: r.id, col_id: c.id })
          if lof_matrix_dropdown_option_values.length>0
            if section_detail.include_other_as_option
              lof_matrix_dropdown_option_values.push "Other..." 
            end

            # do this the other way around. Find all the answer that are already in the system and compare to 
            # options that were given. remove it from the array once we print one out.
            lof_matrix_dropdown_option_values.each do |v|
              sddp, sddp_id, selected = _find_matrix_select_sddp_dt({section: section, section_detail: section_detail, study_id: study_id,
                                                    row_field: r, col_field: c, diagnostic_test_id: diagnostic_test_id,
                                                    value: v, lof_matrix_dropdown_option_values: lof_matrix_dropdown_option_values })
              data = _build_data_array_dt({ :section => section,
                                            :section_detail => section_detail,
                                            :diagnostic_test_id => diagnostic_test_id,
                                            :sddp => sddp,
                                            :sddp_id => sddp_id,
                                            :row => r,
                                            :col => c,
                                            :selected => selected })
              _write_to_csv(study_id, section, data)
            end

          # This must be a text box
          else
            sddp, sddp_id, selected = _find_matrix_select_sddp_dt({section: section, section_detail: section_detail, study_id: study_id,
                                                  row_field: r, col_field: c, diagnostic_test_id: diagnostic_test_id,
                                                  value: nil })
            data = _build_data_array_dt({ :section => section,
                                          :section_detail => section_detail,
                                          :diagnostic_test_id => diagnostic_test_id,
                                          :sddp => sddp,
                                          :sddp_id => sddp_id,
                                          :row => r,
                                          :col => c,
                                          :selected => selected })
            _write_to_csv(study_id, section, data)
          end
        end
      end
    end
  end

  def _find_matrix_select_sddp(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    study_id = params[:study_id]
    row_field = params[:row_field].blank? ? 0 : params[:row_field]
    col_field = params[:col_field].blank? ? 0 : params[:col_field]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    value = params[:value].include?("Other...") ? "" : params[:value] unless params[:value].nil?

    if params[:value].nil?
      sddp = "#{section.to_s}DataPoint".constantize.find(:first,
              :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                               :study_id                                    => study_id,
                               :extraction_form_id                          => @ef_id,
                               :row_field_id                                => row_field.id,
                               :column_field_id                             => col_field.id,
                               :arm_id                                      => arm_id,
                               :outcome_id                                  => outcome_id })
      if sddp.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :arm_id                                      => arm_id,
                                                          :outcome_id                                  => outcome_id)
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end

      return sddp, sddp_id, selected
    end

    if params[:value].include?("Other...")
      lof_matrix_dropdown_option_values = params[:lof_matrix_dropdown_option_values]
      sddps = "#{section.to_s}DataPoint".constantize.find(:all,
               :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                :study_id                                    => study_id,
                                :extraction_form_id                          => @ef_id,
                                :row_field_id                                => row_field.id,
                                :column_field_id                             => col_field.id,
                                :arm_id                                      => arm_id,
                                :outcome_id                                  => outcome_id })
      if sddps.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :value                                       => value,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :arm_id                                      => arm_id,
                                                          :outcome_id                                  => outcome_id)
        sddp_id = ""
        selected = ""
        return sddp, sddp_id, selected
      else
        sddps.each do |dp|
          unless lof_matrix_dropdown_option_values.include?(dp.value)
            sddp = dp
          end

          if sddp.nil?
            sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                              :value                                       => value,
                                                              :study_id                                    => study_id,
                                                              :extraction_form_id                          => @ef_id,
                                                              :row_field_id                                => row_field.id,
                                                              :column_field_id                             => col_field.id,
                                                              :arm_id                                      => arm_id,
                                                              :outcome_id                                  => outcome_id)
            sddp_id = ""
            selected = ""
          else
            sddp_id = dp.id
            selected = "Y"
          end

          return sddp, sddp_id, selected
        end
      end
    else
      sddp = "#{section.to_s}DataPoint".constantize.find(:first,
              :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                               :value                                       => value,
                               :study_id                                    => study_id,
                               :extraction_form_id                          => @ef_id,
                               :row_field_id                                => row_field.id,
                               :column_field_id                             => col_field.id,
                               :arm_id                                      => arm_id,
                               :outcome_id                                  => outcome_id })
      if sddp.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :value                                       => value,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :arm_id                                      => arm_id,
                                                          :outcome_id                                  => outcome_id)
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end
    end

    return sddp, sddp_id, selected
  end

  def _find_matrix_select_sddp_dt(params)  #{{{2
    section = params[:section]
    section_detail = params[:section_detail]
    study_id = params[:study_id]
    row_field = params[:row_field].blank? ? 0 : params[:row_field]
    col_field = params[:col_field].blank? ? 0 : params[:col_field]
    diagnostic_test_id = params[:diagnostic_test_id]
    value = params[:value].include?("Other...") ? "" : params[:value] unless params[:value].nil?

    if params[:value].nil?
      sddp = "#{section.to_s}DataPoint".constantize.find(:first,
              :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                               :study_id                                    => study_id,
                               :extraction_form_id                          => @ef_id,
                               :row_field_id                                => row_field.id,
                               :column_field_id                             => col_field.id,
                               :diagnostic_test_id                          => diagnostic_test_id })
      if sddp.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :diagnostic_test_id                          => diagnostic_test_id)
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end

      return sddp, sddp_id, selected
    end

    if params[:value].include?("Other...")
      lof_matrix_dropdown_option_values = params[:lof_matrix_dropdown_option_values]
      sddps = "#{section.to_s}DataPoint".constantize.find(:all,
               :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                :study_id                                    => study_id,
                                :extraction_form_id                          => @ef_id,
                                :row_field_id                                => row_field.id,
                                :column_field_id                             => col_field.id,
                                :diagnostic_test_id                          => diagnostic_test_id })
      if sddps.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :value                                       => value,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :diagnostic_test_id                          => diagnostic_test_id)
        sddp_id = ""
        selected = ""
        return sddp, sddp_id, selected
      else
        sddps.each do |dp|
          unless lof_matrix_dropdown_option_values.include?(dp.value)
            sddp = dp
          end

          if sddp.nil?
            sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                              :value                                       => value,
                                                              :study_id                                    => study_id,
                                                              :extraction_form_id                          => @ef_id,
                                                              :row_field_id                                => row_field.id,
                                                              :column_field_id                             => col_field.id,
                                                              :diagnostic_test_id                          => diagnostic_test_id)
            sddp_id = ""
            selected = ""
          else
            sddp_id = dp.id
            selected = "Y"
          end

          return sddp, sddp_id, selected
        end
      end
    else
      sddp = "#{section.to_s}DataPoint".constantize.find(:first,
              :conditions => { "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                               :value                                       => value,
                               :study_id                                    => study_id,
                               :extraction_form_id                          => @ef_id,
                               :row_field_id                                => row_field.id,
                               :column_field_id                             => col_field.id,
                               :diagnostic_test_id                          => diagnostic_test_id })
      if sddp.blank?
        sddp = "#{section.to_s}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                                                          :value                                       => value,
                                                          :study_id                                    => study_id,
                                                          :extraction_form_id                          => @ef_id,
                                                          :row_field_id                                => row_field.id,
                                                          :column_field_id                             => col_field.id,
                                                          :diagnostic_test_id                          => diagnostic_test_id)
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end
    end

    return sddp, sddp_id, selected
  end

  def _get_lof_matrix_dropdown_option_values(params)  #{{{2
    lof_matrix_dropdown_option_values = Array.new
    options = MatrixDropdownOption.find(:all, :conditions => { :row_id     => params[:row_id],
                                                               :column_id  => params[:col_id],
                                                               :model_name => "#{params[:section]}".underscore })
    options.each do |option|
      lof_matrix_dropdown_option_values.push option.option_text
    end

    return lof_matrix_dropdown_option_values
  end

  def _single_column_answer_question(params)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    section_fields = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id })
    section_fields.each do |sf|
      sddp = "#{section}DataPoint".constantize.find(:first, :conditions => {
              "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
               :value                                      => sf.option_text,
               :study_id                                   => study_id,
               :extraction_form_id                         => @ef_id,
               :row_field_id                               => 0,
               :column_field_id                            => 0,
               :arm_id                                     => arm_id,
               :outcome_id                                 => outcome_id })
      if sddp.blank?
        sddp = "#{section}DataPoint".constantize.new( "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                 :study_id                                   => study_id,
                 :extraction_form_id                         => @ef_id,
                 :row_field_id                               => 0,
                 :column_field_id                            => 0,
                 :arm_id                                     => arm_id,
                 :outcome_id                                 => outcome_id )
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end

      # Let's do some house cleaning before exporting to csv
      question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip

      arm = Arm.find(:first, :conditions => { :id => arm_id })
      if section==:BaselineCharacteristic && arm_id==0
        arm_title = "All Arms (Total)"
      else
        arm_title = arm.blank? ? "" : arm.title.strip
      end

      outcome = Outcome.find(:first, :conditions => { :id => outcome_id })
      outcome_title = outcome.blank? ? "" : outcome.title.strip

      question = section_detail.question.blank? ? "" : section_detail.question.strip
      value = sddp.value.blank? ? sf.option_text : sddp.value.strip
      notes = sddp.notes.blank? ? "" : sddp.notes.strip
      subquestion = sf.subquestion.blank? ? "" : sf.subquestion.strip
      subquestion_value = sddp.subquestion_value.blank? ? "" : sddp.subquestion_value.strip

      data = [question_type,
              arm_title,
              outcome_title,
              question,
              "",
              "",
              value,
              selected,
              notes,
              subquestion,
              subquestion_value,
              sddp_id]
      _write_to_csv(study_id, section, data)
    end
  end

  def _single_column_answer_question_dt(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:section_detail]

    section_fields = "#{section.to_s}Field".constantize.find(:all,
            :conditions => { "#{section.to_s.underscore}_id".to_sym => section_detail.id })
    section_fields.each do |sf|
      sddp = "#{section}DataPoint".constantize.find(:first, :conditions => {
              "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
               :value                                      => sf.option_text,
               :study_id                                   => study_id,
               :extraction_form_id                         => @ef_id,
               :row_field_id                               => 0,
               :column_field_id                            => 0,
               :diagnostic_test_id                         => diagnostic_test_id })
      if sddp.blank?
        sddp = "#{section}DataPoint".constantize.new( "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
                 :study_id                                   => study_id,
                 :extraction_form_id                         => @ef_id,
                 :row_field_id                               => 0,
                 :column_field_id                            => 0,
                 :diagnostic_test_id                         => diagnostic_test_id )
        sddp_id = ""
        selected = ""
      else
        sddp_id = sddp.id
        selected = sddp.value.blank? ? "" : "Y"
      end

      # Let's do some house cleaning before exporting to csv
      question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip

      diagnostic_test = DiagnosticTest.find(:first, :conditions => { :id => diagnostic_test_id })
      diagnostic_test_title = diagnostic_test.title

      question = section_detail.question.blank? ? "" : section_detail.question.strip
      value = sddp.value.blank? ? sf.option_text : sddp.value.strip
      notes = sddp.notes.blank? ? "" : sddp.notes.strip
      subquestion = sf.subquestion.blank? ? "" : sf.subquestion.strip
      subquestion_value = sddp.subquestion_value.blank? ? "" : sddp.subquestion_value.strip

      data = [question_type,
              diagnostic_test_title,
              question,
              "",
              "",
              value,
              selected,
              notes,
              subquestion,
              subquestion_value,
              sddp_id]
      _write_to_csv(study_id, section, data)
    end
  end

  def _text_question(params)  #{{{2
    study_id = params[:study_id]
    arm_id = params[:arm_id].blank? ? 0 : params[:arm_id]
    outcome_id = params[:outcome_id].blank? ? 0 : params[:outcome_id]
    section = params[:section]
    section_detail = params[:section_detail]

    # The fields table isn't used for text questions.
    sddp = "#{section}DataPoint".constantize.find(:first, :conditions => { 
            "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
             :study_id                                   => study_id,
             :extraction_form_id                         => @ef_id,
             :arm_id                                     => arm_id,
             :outcome_id                                 => outcome_id })
    if sddp.blank?
      sddp = "#{section}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
              :study_id                               => study_id,
              :extraction_form_id                     => @ef_id,
              :arm_id                                 => arm_id,
              :outcome_id                             => outcome_id)
      sddp_id = ""
      selected = ""
    else
      sddp_id = sddp.id
      selected = sddp.value.blank? ? "" : "Y"
    end

    # Let's do some house cleaning before exporting to csv
    question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip

    arm = Arm.find(:first, :conditions => { :id => arm_id })
    if section==:BaselineCharacteristic && arm_id==0
      arm_title = "All Arms (Total)"
    else
      arm_title = arm.blank? ? "" : arm.title.strip
    end

    outcome = Outcome.find(:first, :conditions => { :id => outcome_id })
    outcome_title = outcome.blank? ? "" : outcome.title.strip

    question = section_detail.question.blank? ? "" : section_detail.question.strip
    value = sddp.value.blank? ? "" : sddp.value.strip
    notes = sddp.notes.blank? ? "" : sddp.notes.strip

    data = [question_type,
            arm_title,
            outcome_title,
            question,
            "",
            "",
            value,
            selected,
            notes,
            "",
            "",
            sddp_id]
    _write_to_csv(study_id, section, data)
  end

  def _text_question_dt(params)  #{{{2
    study_id = params[:study_id]
    diagnostic_test_id = params[:diagnostic_test_id]
    section = params[:section]
    section_detail = params[:section_detail]

    # The fields table isn't used for text questions.
    sddp = "#{section}DataPoint".constantize.find(:first, :conditions => { 
            "#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
             :study_id                                   => study_id,
             :extraction_form_id                         => @ef_id,
             :diagnostic_test_detail_field_id            => section_detail.id,
             :diagnostic_test_id                         => diagnostic_test_id })
    if sddp.blank?
      sddp = "#{section}DataPoint".constantize.new("#{section.to_s.underscore}_field_id".to_sym => section_detail.id,
              :study_id                                                                         => study_id,
              :extraction_form_id                                                               => @ef_id,
              :diagnostic_test_id                                                               => diagnostic_test_id )
      sddp_id = ""
      selected = ""
    else
      sddp_id = sddp.id
      selected = sddp.value.blank? ? "" : "Y"
    end

    # Let's do some house cleaning before exporting to csv
    question_type = section_detail.field_type.blank? ? "" : section_detail.field_type.strip

    diagnostic_test = DiagnosticTest.find(:first, :conditions => { :id => diagnostic_test_id })
    diagnostic_test_title = diagnostic_test.blank? ? "" : diagnostic_test.title.strip

    question = section_detail.question.blank? ? "" : section_detail.question.strip
    value = sddp.value.blank? ? "" : sddp.value.strip
    notes = sddp.notes.blank? ? "" : sddp.notes.strip

    data = [question_type,
            diagnostic_test_title,
            question,
            "",
            "",
            value,
            selected,
            notes,
            "",
            "",
            sddp_id]
    _write_to_csv(study_id, section, data)
  end

  def _get_lof_section_details(section)  #{{{2
    "#{section.to_s}".constantize.find(:all, :conditions => { :extraction_form_id => @ef_id })
  end

  def prep_csv(params)  #{{{2
    section_name = params[:section]

    headers = {:KeyQuestion            => ['KQ ID',
                                           'KQ Order Number',
                                           'Key Question'
                                          ],
               :Publication            => ['Project ID',
                                           'Project Title',
                                           'EF Title',
                                           'Section',
                                           'Primary Publication Author',
                                           'Primary Publication Title',
                                           'Primary Publication Country',
                                           'Primary Publication Year',
                                           'Primary Publication Journal',
                                           'Primary Publication Volume',
                                           'Primary Publication Issue',
                                           'Primary Publication Trial Title',
                                           'Primary Publication Identifier Type',
                                           'Primary Publication Identifier',
                                           'Primary Publication PMID',
                                           'Study ID',
                                          ],
               :DesignDetail           => ['Question Type',
                                           'Arm Title',
                                           'Outcome Title',
                                           'Question',
                                           'Row Option Text',
                                           'Col Option Text',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Follow-up Question',
                                           'Follow-up Value',
                                           'Data Point ID'
                                          ],
               :DiagnosticTest         => ['Diagnostic Test',
                                           'Diagnostic Test Type',
                                           'Diagnostic Test Description',
                                           'Diagnostic Test Notes',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Is suggested by lead? (Y=Yes, *Blank*=No)',
                                           'Diagnostic Test Threshold',
                                          ],
               :DiagnosticTestDetail   => ['Question Type',
                                           'Diagnostic Test Title',
                                           'Question',
                                           'Row Option Text',
                                           'Col Option Text',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Follow-up Question',
                                           'Follow-up Value',
                                           'Data Point ID'
                                          ],
               :Arm                    => ['Arm Title',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Is suggested by lead? (Y=Yes, *Blank*=No)',
                                          ],
               :ArmDetail              => ['Question Type',
                                           'Arm Title',
                                           'Outcome Title',
                                           'Question',
                                           'Row Option Text',
                                           'Col Option Text',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Follow-up Question',
                                           'Follow-up Value',
                                           'Data Point ID'
                                          ],
               :BaselineCharacteristic => ['Question Type',
                                           'Arm Title',
                                           'Outcome Title',
                                           'Question',
                                           'Row Option Text',
                                           'Col Option Text',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Follow-up Question',
                                           'Follow-up Value',
                                           'Data Point ID'
                                          ],
               :Outcome                => ['Outcome Title',
                                           'Outcome Description',
                                           'Outcome Type',
                                           'Outcome Selected? (Y=Yes, *Blank*=No)',
                                           'Is suggested by lead? (Y=Yes, *Blank*=No)',
                                           'Population',
                                           'Population Selected? (Y=Yes, *Blank*=No)',
                                           'Population Description',
                                           'Timepoint',
                                           'Time Unit',
                                           'Timepoint Selected? (Y=Yes, *Blank*=No)',
                                           'Outcome ID',
                                           'Subgroup ID',
                                           'Timepoint ID',
                                          ],
               :OutcomeDetail          => ['Question Type',
                                           'Arm Title',
                                           'Outcome Title',
                                           'Question',
                                           'Row Option Text',
                                           'Col Option Text',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Follow-up Question',
                                           'Follow-up Value',
                                           'Data Point ID'
                                          ],
               :AdverseEvent           => ['Arm Title',
                                           'Adverse Event',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Adverse Event Description',
                                           'Adverse Event Column',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Data Point ID'
                                          ],
               :QualityDimension       => ['Dimension',
                                           'Value',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes',
                                           'Instructions'
                                          ],
               :QualityRating          => ['Quality Guideline Used',
                                           'Select Current Overall Rating',
                                           'Selected? (Y=Yes, *Blank*=No)',
                                           'Notes on this Rating'
                                          ]}

    filename = "#{@p_id}_#{@ef_id}_#{section_name}.csv"
    @filepath_lookup[section_name] = @EXPORT_PATH + filename

    CSV.open(@filepath_lookup[section_name], "wb") do |csv|
      if section_name==:Publication
        csv << headers[:Publication]
      else
        csv << headers[:Publication] + headers[section_name]
      end
    end
  end

  def short_section_name  #{{{2
    {:KeyQuestion => 'questions',
     :Publication => 'publications',
     :DesignDetail => 'design',
     :DiagnosticTest => 'diagnostics',
     :DiagnosticTestDetail => 'diagnostic_test_details',
     :Arm => 'arms',
     :ArmDetail => 'arm_details',
     :BaselineCharacteristic => 'baselines',
     :Outcome => 'outcomes',
     :OutcomeDetail => 'outcome_details',
     :AdverseEvent => 'adverse',
     :QualityDimension => 'quality'}
  end
end
