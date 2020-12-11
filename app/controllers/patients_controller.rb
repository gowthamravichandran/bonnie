class PatientsController < ApplicationController
  include MeasureHelper
  include PatientImportHelper
  before_action :authenticate_user!
  prepend_view_path(Rails.root.join('lib/templates/'))

  def update
    old_patient = CQM::Patient.by_user(current_user).find(cqm_patient_params[:id])
    begin
      updated_patient = CQM::Patient.transform_json(cqm_patient_params)
    rescue Mongoid::Errors::UnknownAttribute
      render json: { status: "error", messages: "Patient not properly structured for creation." }, status: :internal_server_error
      return
    end
    populate_measure_ids(updated_patient)
    updated_patient._id = old_patient._id if old_patient
    updated_patient.user_id = current_user._id
    updated_patient.upsert
    render :json => updated_patient
  end

  def create
    begin
      patient = CQM::Patient.transform_json(cqm_patient_params)
      patient[:user_id] = current_user.id
    rescue Mongoid::Errors::UnknownAttribute
      render json: { status: "error", messages: "Patient not properly structured for creation." }, status: :internal_server_error
      return
    end
    populate_measure_ids(patient)
    patient.save!
    render :json => patient
  end

  def destroy
    patient = CQM::Patient.by_user(current_user).find(params[:id])
    CQM::Patient.by_user(current_user).find(params[:id]).destroy
    render :json => patient.as_json
  end

  def qrda_export
    if params[:patients]
      # if patients are given, they're from the patient bank; use those patients
      patients = CQM::Patient.where(is_shared: true).find(params[:patients])
    else
      patients = CQM::Patient.by_user(current_user)
      unless current_user.portfolio?
        patients = patients.where({ :measure_ids.in => [params[:set_id]] })
      end
      measure = CQM::Measure.by_user(current_user).where({ :set_id => params[:set_id] })
    end

    qrda_errors = {}
    html_errors = {}

    stringio = Zip::ZipOutputStream::write_buffer do |zip|
      patients.each_with_index do |patient, index|
        # Use defined measure if available, else get the specific measure for this patient
        patient_measure = measure || get_associated_measure(patient)
        # attach the QRDA export, or the error
        begin
          qrda = qrda_patient_export(patient, patient_measure) # allow error to stop execution before header is written
          zip.put_next_entry(File.join("qrda", "#{index + 1}_#{patient.familyName}_#{patient.givenNames[0]}.xml"))
          zip.puts qrda
        rescue Exception => e
          qrda_errors[patient.id] = e
        end
        # attach the HTML export, or the error
        begin
          html = QdmPatient.new(patient, true).render
          zip.put_next_entry(File.join("html", "#{index + 1}_#{patient.familyName}_#{patient.givenNames[0]}.html"))
          zip.puts html
        rescue Exception => e
          html_errors[patient.id] = e
        end
      end
      # add the summary content if there are results
      if (params[:results] && !params[:patients])
        measure = CQM::Measure.by_user(current_user).where({ :set_id => params[:set_id] }).first
        zip.put_next_entry("#{measure.cms_id}_patients_results.html")
        zip.puts measure_patients_summary(patients, params[:results].permit!.to_h, qrda_errors, html_errors, measure)
      end
    end
    cookies[:fileDownload] = "true" # We need to set this cookie for jquery.fileDownload
    stringio.rewind
    measure = CQM::Measure.by_user(current_user).where({ :set_id => params[:set_id] }).first
    filename = if params[:set_id] then
                 "#{measure.cms_id}_patient_export.zip"
               else
                 "bonnie_patient_export.zip"
               end
    send_data stringio.sysread, :type => 'application/zip', :disposition => 'attachment', :filename => filename
  end

  def excel_export
    cookies[:fileDownload] = "true" # We need to set this cookie for jquery.fileDownload
    package = PatientExport.export_excel_cql_file(JSON.parse(params[:calc_results]),
                                                  JSON.parse(params[:patient_details]),
                                                  JSON.parse(params[:population_details]),
                                                  JSON.parse(params[:statement_details]),
                                                  params[:measure_set_id])
    send_data package.to_stream.read, type: "application/xlsx", filename: "#{params[:file_name]}.xlsx"
  end

  def share_patients
    patients = CQM::Patient.by_user(current_user)
    patients = patients.where({ :measure_ids.in => [params[:set_id]] })
    # set patient measure_ids to those selected in the UI
    measure_ids = params[:selected] || []
    # plus the set_id of the measure the patients are being shared from
    measure_ids.push(params[:set_id])
    # set measure_ids for all patients on the current measure
    patients.each do |patient|
      patient.measure_ids = measure_ids
      patient.save
    end
    redirect_to root_path
  end

  def import_patients
    measure_id = params[:measure_id]
    uploaded_file = params[:patient_import_file]

    raise UploadedFileNotZip.new if uploaded_file.content_type != "application/zip"

    measure = CQM::Measure.where(id: measure_id).first
    raise MeasureUpdateMeasureNotFound.new if measure.nil?

    json_from_zip_file = ""

    Zip::File.open(uploaded_file.path) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|

        raise ZipEntryNotJson.new if json_from_zip_file.length > 0
        raise ZipEntryNotJson.new if !entry.name.end_with?(".json")

        json_from_zip_file = entry.get_input_stream.read
      end
    end

    patients_array = JSON.parse(json_from_zip_file)
    patients = patients_array.map { |patient_json| CQM::Patient.transform_json(patient_json) }

    # validate all patients first so we dont have partial upserts
    patients.each do |patient|
      patient.measure_ids.clear
      patient.measure_ids.push(measure.set_id)

      patient.expected_values.each { |v| v["measure_id"] = measure.set_id }
      patient[:user_id] = current_user._id

      raise MeasureLoadingOther.new if !patient.validate
    end

    patients.each do |patient|
      patient.upsert
    end

  rescue StandardError => e
    puts e.backtrace
    flash[:error] = turn_exception_into_shared_error_if_needed(e).front_end_version
    redirect_to "#{root_path}#measures/#{params[:set_id]}"
  end

  private

  def cqm_patient_params
    # It would be better if we could explicitely check all nested params, but given the number and depth of
    # them, it just isn't feasible.  We will instead rely on Mongoid::Errors::UnknownAttribute to be thrown
    # if any undeclared properties make it into the cqmPatient hash.  This is only possible because currently
    # no models being instantiated here include the Mongoid::Attributes::Dynamic module.
    params.require(:cqmPatient).permit!.to_h
  end

  def populate_measure_ids(patient)
    unless patient['measure_ids'].nil?
      patient['measure_ids'].uniq!
    end
  end

  def convert_to_hash(key, array)
    Hash[array.map { |element| [element[key], element.except(key)] }]
  end

  def get_associated_measure(patient)
    CQM::Measure.where(set_id: patient.measure_ids.first)
  end

  def qrda_patient_export(patient, measure)
    start_time = DateTime.parse(measure[0].measure_period['low']['value'])
    end_time = DateTime.parse(measure[0].measure_period['high']['value'])
    options = { start_time: start_time, end_time: end_time }
    if patient.qdmPatient.get_data_elements('patient_characteristic', 'payer').empty?
      payer_codes = [{ 'code' => '1', 'system' => '2.16.840.1.113883.3.221.5', 'codeSystem' => 'SOP' }]
      patient.qdmPatient.dataElements.push QDM::PatientCharacteristicPayer.new(dataElementCodes: payer_codes, relevantPeriod: QDM::Interval.new(patient.qdmPatient.birthDatetime, nil))
    end
    Qrda1R5.new(patient, measure, options).render
  end

  def measure_patients_summary(patients, results, qrda_errors, html_errors, measure)
    render_to_string partial: "index.html.erb", locals: { measure: measure, results: results, records: patients, html_errors: html_errors, qrda_errors: qrda_errors }
  end

end
