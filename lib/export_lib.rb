# encoding: UTF-8

require 'fileutils'

class Exporter

  def initialize(p_id, ef_id, is_diagnostic)
    @EXPORT_PATH = './output/'
    @p_id        = p_id
    @ef_id       = ef_id
    @lof_errors  = Array.new
    @common_info = Hash.new

    # Build a list of sections. Each section will have its own csv file
    @sections = [:KeyQuestions, :Publications, :DesignDetails]
    if is_diagnostic
      @sections.concat([:DiagnosticTests, :DiagnosticTestDetails])
    else
      @sections.concat([:Arms, :ArmDetails])
    end
    @sections.concat([:BaselineCharacteristics, :Outcomes, :OutcomeDetails,
                      :AdverseEvents, :QualityDimensions, :QualityRatings])
  end

  def get_project_id
    @p_id
  end

  def get_extraction_form_id
    @ef_id
  end

  def build_arm_csv
  end

  def build_outcome_csv
  end

  def build_details_csv
  end

  # We get the list of study ids by their association to the extraction form
  # This can be found in the study_extraction_forms table
  def get_lof_study_ids
    lof_study_ids = []
    sefs = StudyExtractionForm.find(:all, :conditions => { :extraction_form_id => @ef_id })
    sefs.each do |s|
      lof_study_ids.push s.study_id
    end
    return lof_study_ids
  end

  def export
    lof_study_ids = get_lof_study_ids
    if lof_study_ids.blank?
      @lof_errors.push "Skipping extraction form id #{@ef_id}. No associated studies found."
    else
      errors = _build_export(lof_study_ids=lof_study_ids)
      @lof_errors.concat errors
    end
  end

  def log_errors
    unless @lof_errors.blank?
      puts " ++++++++++ EF ID #{@ef_id} ERRORS ++++++++++"
      puts "  ++++++++++++++++++++++++++++++++++++++++++++"
      @lof_errors.each do |e|
        #!!! Write these to a log file instead by extraction form id
        puts e
      end
    end
  end

  def _build_export(lof_study_ids)
    errors = []

    # We skip checking QualityRatings section because it is part of the QualityDimensions section
    sections = @sections - [:QualityRatings]

    lof_study_ids.each do |id|
      puts "working on id #{id}"
      sections.each do |s|
        # Check if section is to be processed.
        efs = ExtractionFormSection.find(:first, :conditions => { :extraction_form_id => @ef_id,
                                                                   :section_name => short_section_name[s] })
        if efs.blank?
          errors << "  Unable to find extraction form section entry for study id #{id}, section name #{s}"
        else
          if efs.included
            _process_section(study_id=id, section=s)
            # Since we made QualityRatings dependent on the QualityDimensions section,
            # we need to process QualityRatings section if QualityDimensions are included
            if s==:QualityDimensions
              _process_section(study_id=id, section=:QualityRatings)
            end
          elsif s==:KeyQuestions || s==:Publications
            # KeyQuestions and Publications sections are set to false in the included cell
            # by default. So we include them regardless of the .included check.
            _process_section(study_id=id, section=s)
          else
            errors << "  INFO: Section #{s} is not included on extraction form #{@ef_id}"
          end
        end
      end
    end

    return errors
  end

  def _process_section(study_id, section)
    prep_csv(section=section)

    case section
    when :KeyQuestions
      _process_key_questions(study_id=study_id)
    when :Publications
    when :DesignDetails
    when :DiagnosticTests
    when :DiagnosticTestDetails
    when :Arms
    when :ArmDetails
    when :BaselineCharacteristics
    when :Outcomes
    when :OutcomeDetails
    when :AdverseEvents
    when :QualityDimensions
    when :QualityRatings
    else
      @lof_errors << "Failure to sort section #{section} for study ID #{study_id} extraction form ID #{@ef_id}"
    end
  end

  def _get_lof_kq_ids(study_id)
    lof_kq_ids = Array.new

    study_key_questions = StudyKeyQuestion.find_all_by_study_id(study_id)
    study_key_questions.each do |s|
      lof_kq_ids << s.key_question_id
    end
    return lof_kq_ids
  end

  #!!! TODO
  def _get_common_info_hash(study_id)
  end

  def _write_kq_to_csv(study_id)
    @common_info[study_id.to_sym] ||= _get_common_info_hash(study_id=study_id)
  end

  def _process_key_questions(study_id)
    lof_kq_ids = _get_lof_kq_ids(study_id=study_id)
    lof_kqs = KeyQuestion.find(:all, :conditions => ["id in (?)", lof_kq_ids])
    lof_kqs.each do |kq|
      #puts "Found the following KeyQuestions: #{kq.inspect}"
      #gets
      _write_kq_to_csv(study_id=study_id)
    end
  end

  def prep_csv(section_name)
    headers = {:KeyQuestions            => ['KQ ID', 'KQ Order Number', 'Key Question'],
               :Publications            => ['Project ID', 'Project Title', 'EF Title', 'Section',
                                            'Primary Publication Title', 'Primary Publication Author',
                                            'Primary Publication Countyr', 'Primary Publication Year',
                                            'Primary Publication PMID', 'Primary Publication Journal',
                                            'Primary Publication Volume', 'Primary Publication Issue',
                                            'Primary Publication Trial Title', 'Primary Publication Identifier Type',
                                            'Primary Publication Identifier', 'Study ID'],
               :DesignDetails           => ['Question Type', 'Arm title', 'Outcome Title', 'Question',
                                            'Row Option Text', 'Col Option Text', '***VALUE***', '***NOTES***',
                                            'Follow-up?', '***FOLLOW-UP VALUE***', 'Data Point ID'],
               :DiagnosticTests         => [],
               :DiagnosticTestDetails   => [],
               :Arms                    => [],
               :ArmDetails              => [],
               :BaselineCharacteristics => [],
               :Outcomes                => [],
               :OutcomeDetails          => [],
               :AdverseEvents           => [],
               :QualityDimensions       => [],
               :QualityRatings          => []}

    filename = "#{@p_id}_#{@ef_id}_#{section_name}.csv"
    filepath = @EXPORT_PATH + filename

    FileUtils.mkpath @EXPORT_PATH unless File.exists? @EXPORT_PATH
    
    CSV.open(filepath, "wb") do |csv|
      csv << headers[:Publications] + headers[section_name]
    end
  end

  def short_section_name
    {:KeyQuestions => 'questions',
     :Publications => 'publications',
     :DesignDetails => 'design',
     :DiagnosticTests => 'diagnostics',
     :DiagnosticTestDetails => 'diagnostic_test_details',
     :Arms => 'arms',
     :ArmDetails => 'arm_details',
     :BaselineCharacteristics => 'baselines',
     :Outcomes => 'outcomes',
     :OutcomeDetails => 'outcome_details',
     :AdverseEvents => 'adverse',
     :QualityDimensions => 'quality'}
  end
end
