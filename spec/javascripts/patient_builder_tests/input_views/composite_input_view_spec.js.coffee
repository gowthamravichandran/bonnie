describe 'InputView', ->

  describe 'CompositeView', ->

    beforeEach ->
      jasmine.getJSONFixtures().clearCache()
      @measure = loadMeasureWithValueSets 'cqm_measure_data/CMS134v6/CMS134v6.json', 'cqm_measure_data/CMS134v6/value_sets.json'
      @patients = new Thorax.Collections.Patients [getJSONFixture('patients/CMS134v6/Elements_Test.json')], parse: true
      @patient = @patients.at(0)
      sourceDataCriteria = @patient.get('source_data_criteria')
      @dataElements = sourceDataCriteria.map (sdc) -> sdc.get('qdmDataElement')
      @laboratoryTest = @dataElements.filter((element) -> element.qdmCategory is 'laboratory_test')[0]
      @encounterPerformed = @dataElements.filter((element) -> element.qdmCategory is 'encounter')[0]
      @view = new Thorax.Views.InputCompositeView
        schema: @laboratoryTest.schema.paths['components'].schema,
        typeName: 'Component',
        codeSystemMap: @measure.codeSystemMap(),
        cqmValueSets: @measure.get('cqmValueSets')
      @facilityLocationView = new Thorax.Views.InputCompositeView
        schema: @encounterPerformed.schema.paths['facilityLocations'].schema,
        typeName: 'FacilityLocation',
        codeSystemMap: @measure.codeSystemMap(),
        cqmValueSets: @measure.get('cqmValueSets')
      @facilityLocationView.render()
      @view.render()

    it 'initializes', ->
      expect(@view.hasValidValue()).toBe false
      expect(@view.value).toBe null

    it 'populates component views', ->
      expect(@view.componentViews.length).toEqual 2
      # A Component has a code and a result
      expect(@view.componentViews.map((view) -> view.name)).toContain('code')
      expect(@view.componentViews.map((view) -> view.name)).toContain('result')

    it 'populates facilityLocation views', ->
      expect(@facilityLocationView.componentViews.length).toEqual 2
      # A Facility Location has a code and a location period
      expect(@facilityLocationView.componentViews.map((view) -> view.name)).toContain('code')
      expect(@facilityLocationView.componentViews.map((view) -> view.name)).toContain('locationPeriod')

    xit 'populates ResultComponent views', ->
      # TODO: Find measure that uses this

    xit 'populates Id views', ->
      # TODO: Find measure that uses this

    it 'allows for a Component to be added', ->
      expect(@view.value).toBeNull()
      # Both the valueset/code and the result must be valid to add a Component
      @view.$('select[name="valueset"]').val("2.16.840.1.113883.3.464.1003.101.12.1001").change()
      # No need to set code, one is selected by default
      expect(@view.value).toBeNull()
      @view.$('select[name="type"]').val('Quantity').change()
      @view.$('input[name="value_unit"] > option[value="mm"]').val('mm').change()
      expect(@view.value).toBeNull() # Still not valid without result
      @view.componentViews[1].view.inputView.$('input[name="value_value"]').val('10').change()
      expect(@view.value._type).toEqual 'QDM::Component' # Default unit is '' which is valid
      @view.componentViews[1].view.inputView.$('input[name="value_unit"]').val('cc').change()
      expect(@view.value).toBeNull() # Null with invalid ucum unit
      @view.componentViews[1].view.inputView.$('input[name="value_unit"]').val('cm3').change()
      expect(@view.value._type).toEqual 'QDM::Component'

    it 'allows for a FacilityLocation to be added', ->
      expect(@facilityLocationView.value).toBeNull()
      # Both valueset/code and locationPeriod must be input
      @facilityLocationView.$('select[name="valueset"]').val("2.16.840.1.113883.3.464.1003.101.12.1001").change()
      # No need to set code, one is selected by default
      expect(@facilityLocationView.value._type).toEqual('QDM::FacilityLocation') # null locationPeriod by default is allowed

      # Enable start and populate with default datetime
      @facilityLocationView.$('input[name="start_date_is_defined"]').click()
      expect(@facilityLocationView.value._type).toEqual('QDM::FacilityLocation')

      # Enable end and populate with default datetime
      @facilityLocationView.$('input[name="end_date_is_defined"]').click()
      expect(@facilityLocationView.value._type).toEqual('QDM::FacilityLocation')