describe 'DataCriteriaHelpers', ->

  describe 'Observation attributes', ->
    it 'should support Observation.status', ->
      DataCriteriaAsserts.assertCode('Observation', 'status', 'status', (fhirResource) -> cqm.models.ObservationStatus.isObservationStatus(fhirResource.status))

    it 'should support Observation.category', ->
      DataCriteriaAsserts.assertCodeableConcept('Observation', 'category', 'category')

    it 'should support Observation.value', ->
      observationAttrs = DataCriteriaHelpers.DATA_ELEMENT_ATTRIBUTES['Observation']
      value = observationAttrs[1]
      expect(value.path).toEqual 'value'
      expect(value.title).toEqual 'value'
      expect(value.types).toEqual ['Boolean', 'CodeableConcept', 'DateTime', 'Integer', 'Period',
        'Quantity', 'Range', 'Ratio', 'SampleData', 'String', 'Time']

      # set Boolean value
      valueBoolean = cqm.models.PrimitiveBoolean.parsePrimitive(true)
      fhirResource = new cqm.models.Observation()
      value.setValue(fhirResource, valueBoolean)
      expect(fhirResource.value.value).toEqual valueBoolean.value
      attrValue = value.getValue(fhirResource)
      expect(attrValue.value).toEqual valueBoolean.value

      # set DateTime value
      valueDateTime = new cqm.models.CQL.DateTime(2012, 2, 2, 8, 45, 0, 0, 0)
      value.setValue(fhirResource, valueDateTime)
      expect(fhirResource.value.value).toEqual valueDateTime.toString()

      # set CodeableConcept value
      coding = cqm.models.Coding.parse({system: 'SNOMEDCT', code:'123456', version: 'version'})
      value.setValue(fhirResource, coding)
      attrValue = value.getValue(fhirResource)
      expect(attrValue.system.value).toEqual coding.system.value
      expect(attrValue.code.value).toEqual coding.code.value
      expect(attrValue.version.value).toEqual coding.version.value

