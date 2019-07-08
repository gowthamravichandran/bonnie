describe 'InputView', ->

  describe 'RatioView', ->

    it 'starts with no numerator and denominator then valid after entry', ->
      view = new Thorax.Views.InputRatioView()
      view.render()
      spyOn(view, 'trigger')

      expect(view.hasValidValue()).toBe false
      expect(view.value).toBe null

      view.$('.ratio-numerator input[name="value_value"]:first').val('200').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.hasValidValue()).toBe false
      expect(view.value).toEqual null

      view.$('.ratio-numerator input[name="value_unit"]:first').val('mg').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.hasValidValue()).toBe false
      expect(view.value).toEqual null

      view.$('.ratio-denominator input[name="value_value"]').val('1').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.hasValidValue()).toBe true
      expect(view.value).toEqual new cqm.models.CQL.Ratio(
        numerator: new cqm.models.CQL.Quantity(value: 200, unit: 'mg')
        denominator: new cqm.models.CQL.Quantity(value: 1, unit: ''))

      view.$('.ratio-denominator input[name="value_unit"]').val('L').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.hasValidValue()).toBe true
      expect(view.value).toEqual new cqm.models.CQL.Ratio(
        numerator: new cqm.models.CQL.Quantity(value: 200, unit: 'mg')
        denominator: new cqm.models.CQL.Quantity(value: 1, unit: 'L'))
    
    
    it 'starts with initial quantity and becomes invalid after bad unit entry, valid again after fix', ->
      view = new Thorax.Views.InputRatioView(initialValue: new cqm.models.CQL.Ratio(
        numerator: new cqm.models.CQL.Quantity(value: 200, unit: 'mg')
        denominator: new cqm.models.CQL.Quantity(value: 1, unit: 'L')))
      view.render()
      spyOn(view, 'trigger')

      expect(view.hasValidValue()).toBe true
      expect(view.value).toEqual new cqm.models.CQL.Ratio(
        numerator: new cqm.models.CQL.Quantity(value: 200, unit: 'mg')
        denominator: new cqm.models.CQL.Quantity(value: 1, unit: 'L'))
      expect(view.$('.ratio-numerator input[name="value_value"]').val()).toEqual '200'
      expect(view.$('.ratio-numerator input[name="value_unit"]').val()).toEqual 'mg'
      expect(view.$('.ratio-denominator input[name="value_value"]').val()).toEqual '1'
      expect(view.$('.ratio-denominator input[name="value_unit"]').val()).toEqual 'L'

      # enter invalid unit
      view.$('.ratio-numerator input[name="value_unit"]').val('laughs').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.$('.ratio-numerator .quantity-control-unit').hasClass('has-error')).toBe true
      expect(view.hasValidValue()).toBe false
      expect(view.value).toEqual null

      # enter valid unit
      view.$('.ratio-numerator input[name="value_unit"]').val('kg').change()
      expect(view.trigger).toHaveBeenCalledWith('valueChanged', view)
      expect(view.hasValidValue()).toBe true
      expect(view.value).toEqual new cqm.models.CQL.Ratio(
        numerator: new cqm.models.CQL.Quantity(value: 200, unit: 'kg')
        denominator: new cqm.models.CQL.Quantity(value: 1, unit: 'L'))