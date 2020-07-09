class MeasuresController < ApplicationController
  include MeasureHelper

  skip_before_action :verify_authenticity_token, only: [:show]

  respond_to :json, :js, :html

  def show
    # TODO: I think skippable_fields can be removed with the 'without(*skippable_fields)' below
    skippable_fields = [:map_fns, :record_ids, :measure_attributes]
    @measure = CQM::Measure.by_user(current_user).without(*skippable_fields).where(id: params[:id]).first
    raise Mongoid::Errors::DocumentNotFound unless @measure
    if stale? last_modified: @measure.updated_at.try(:utc), etag: @measure.cache_key
      raw_json = @measure.as_document.as_json(except: skippable_fields)
      value_sets = @measure.value_sets
      raw_json['value_sets'] = value_sets.as_json
      @measure_json = MultiJson.encode(raw_json)
      respond_with @measure do |format|
        format.json { render json: @measure_json }
      end
    end
  end

  def create
    if !params[:measure_file]
      flash[:error] = {title: "Error Loading Measure", body: "You must specify a Measure Authoring tool measure export to use."}
      redirect_to "#{root_path}##{params[:redirect_route]}"
      return
    end

    begin
      vsac_tgt = obtain_ticket_granting_ticket
    rescue Util::VSAC::VSACError => e
      raise convert_vsac_error_into_shared_error(e)
    end

    params[:vsac_tgt] = vsac_tgt[:ticket]
    params[:vsac_tgt_expires_at] = vsac_tgt[:expires]

    measures, main_hqmf_set_id = persist_measure(params[:measure_file], params, current_user)
    redirect_to "#{root_path}##{params[:redirect_route]}"
  rescue StandardError => e
    # also clear the ticket granting ticket in the session if it was a VSACTicketExpiredError
    session[:vsac_tgt] = nil if e.is_a?(VSACTicketExpiredError)
    flash[:error] = turn_exception_into_shared_error_if_needed(e).front_end_version
    redirect_to "#{root_path}##{params[:redirect_route]}"
  end

  def destroy
    measure = CQM::Measure.by_user(current_user).where(id: params[:id]).first

    if measure.component
      render status: :bad_request, json: {error: "Component measures can't be deleted individually."}
      return
    elsif measure.composite
      # If the measure if a composite, delete all the associated components
      measure.component_hqmf_set_ids.each do |component_hqmf_set_id|
        CQM::Measure.by_user(current_user).where(hqmf_set_id: component_hqmf_set_id).first.destroy_self_and_child_docs
      end
    end
    measure.destroy_self_and_child_docs

    render :json => measure
  end

  def finalize
    measure_finalize_data = params.values.select {|p| p['hqmf_id']}.uniq
    measure_finalize_data.each do |data|
      measure = CQM::Measure.by_user(current_user).where(hqmf_id: data['hqmf_id']).first
      begin
        # TODO: should this do the same for component measures?
        Measures::CqlLoader.update_population_set_and_strat_titles(measure, data['titles'])
        measure.save!
      rescue Exception => e
        operator_error = true
        flash[:error] = {title: "Error Loading Measure", summary: "Error Finalizing Measure", body: "An unexpected error occurred while finalizing this measure.  Please delete the measure, re-package and re-export the measure from the MAT, and re-upload the measure."}
      ensure
        # These 2 steps need to be run even if there was an error, otherwise there will be an infinite loop with the finalize dialog
        measure['needs_finalize'] = false
        measure.save!
      end
    end
    redirect_to root_path
  end

  def measurement_period
    measure = CQM::Measure.by_user(current_user).where(id: params[:id]).first
    year = params[:year]
    is_valid_year = year.to_i == year.to_f && year.length == 4 && year.to_i >= 1 && year.to_i <= 9999

    if is_valid_year
      original_year = measure.measure_period['low']['value'][0..3]
      year_shift = year.to_i - original_year.to_i
      successful_patient_shift = if !params[:measurement_period_shift_dates].nil?
                                   shift_years(measure, year_shift)
                                 else # No patients to shift dates on, so just save to measure
                                   true
                                 end
      if successful_patient_shift
        measure.measure_period['low']['value'] = year + '01010000' # Jan 1, 00:00
        measure.measure_period['high']['value'] = year + '12312359' # Dec 31, 23:59
        measure.save!
        if measure.composite?
          measure.component_hqmf_set_ids.each do |hqmf_set_id|
            component_measure = CQM::Measure.by_user(current_user).where(hqmf_set_id: hqmf_set_id).first
            component_measure.measure_period['low']['value'] = year + '01010000' # Jan 1, 00:00
            component_measure.measure_period['high']['value'] = year + '12312359' # Dec 31, 23:59
            component_measure.save!
          end
        end
      end

    else
      flash[:error] = { title: 'Error Updating Measurement Period',
                        summary: 'Error Updating Measurement Period',
                        body: 'Invalid year selected. Year must be 4 digits and between 1 and 9999' }
    end

    redirect_to "#{root_path}##{params[:redirect_route]}"
  end

  private

  def persist_measure(uploaded_file, params, user)
    measure =
      if params[:hqmf_set_id].present?
        update_measure(uploaded_file: uploaded_file,
                      target_id: params[:hqmf_set_id],
                      value_set_loader: build_vs_loader(params, false),
                      user: user)
      else
        create_measure(uploaded_file: uploaded_file,
                      measure_details: retrieve_measure_details(params),
                      value_set_loader: build_vs_loader(params, false),
                      user: user)
      end
    #check_measures_for_unsupported_data_elements(measures)
    return measure, measure.set_id
  end

  def check_measures_for_unsupported_data_elements(measures)
    measures.each do |measure|
      if (measure.source_data_criteria.select {|sdc| sdc.qdmCategory == "related_person" }).length() > 0
        measure.destroy_self_and_child_docs
        raise MeasureLoadingUnsupportedDataElement.new("Related Person")
      end
    end
  end

  def retrieve_measure_details(params)
    return {
      'episode_of_care'=>params[:calculation_type] == 'episode',
      'calculate_sdes'=>params[:calc_sde]
    }
  end

  def shift_years(measure, year_shift)
    # Copy the patients to make sure there are no errors before saving every patient
    patients = CQM::Patient.by_user_and_hqmf_set_id(current_user, measure.hqmf_set_id).all.entries
    errored_patients = []
    patients.each do |patient|
      begin
        patient_birthdate_year = patient.qdmPatient.birthDatetime.year
        if year_shift + patient_birthdate_year > 9999 || year_shift + patient_birthdate_year < 0001
          raise RangeError
        end
        patient.qdmPatient.birthDatetime = shift_birth_datetime(patient.qdmPatient.birthDatetime, year_shift)
        patient.qdmPatient.dataElements.each do |data_element|
          data_element.shift_years(year_shift)
        end
      rescue RangeError => e
        errored_patients << patient
      end
    end

    if errored_patients.empty?
      patients.each(&:save!)
      return true
    else
      body_text = 'Element(s) on '
      errored_patients.each { |patient| body_text += patient.givenNames[0] + ' ' + patient.familyName + ', '}
      body_text += 'could not be shifted. Please make sure shift will keep all years between 1 and 9999'
      flash[:error] = { title: 'Error Updating Measurement Period',
                        summary: 'Error Updating Measurement Period',
                        body: body_text }
      return false
    end
  end

  def shift_birth_datetime(birth_datetime, year_shift)
    if birth_datetime.month == 2 && birth_datetime.day == 29 && !Date.leap?(year_shift + birth_datetime.year)
      birth_datetime.change(year: year_shift + birth_datetime.year, day: 28)
    else
      birth_datetime.change(year: year_shift + birth_datetime.year)
    end
  end

  def obtain_ticket_granting_ticket
    # Retreive a (possibly) existing ticket granting ticket
    ticket_granting_ticket = session[:vsac_tgt]

    # If the ticket granting ticket doesn't exist (or has expired), get a new one
    if ticket_granting_ticket.nil?
      # The user could open a second browser window and remove their ticket_granting_ticket in the session after they
      # prepeared a measure upload assuming ticket_granting_ticket in the session in the first tab

      # First make sure we have credentials to attempt getting a ticket with. Throw an error if there are no credentials.
      if params[:vsac_username].nil? || params[:vsac_password].nil?
        raise Util::VSAC::VSACNoCredentialsError.new
      end

      # Retrieve a new ticket granting ticket by creating the api class.
      api = Util::VSAC::VSACAPI.new(config: APP_CONFIG['vsac'], username: params[:vsac_username], password: params[:vsac_password])
      ticket_granting_ticket = api.ticket_granting_ticket

      # Create a new ticket granting ticket session variable
      session[:vsac_tgt] = ticket_granting_ticket
      return ticket_granting_ticket

    # If it does exist, let the api test it
    else
      api = Util::VSAC::VSACAPI.new(config: APP_CONFIG['vsac'], ticket_granting_ticket: ticket_granting_ticket)
      return api.ticket_granting_ticket
    end
  end
end
