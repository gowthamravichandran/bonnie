
# Input view for String types.
class Thorax.Views.InputStringView extends Thorax.Views.BonnieView
  template: JST['patient_builder/inputs/string']

  # Expected options to be passed in using the constructor options hash:
  #   initialValue - string - Optional. Initial value of string.
  #   allowNull - boolean - Optional. If a null or empty string is allowed. Defaults to true.
  #   placeholder - string - Optional. placeholder text to show. will use 'string' if not specified
  initialize: ->
    if @initialValue?
      @value = @initialValue
    else
      @value = null

    if !@hasOwnProperty('allowNull')
      @allowNull = true

  events:
    'change input': 'handleInputChange'
    'keyup input': 'handleInputChange'

  # checks if the value in this view is valid. returns true or false. this is used by the attribute entry view to determine
  # if the add button should be active or not
  hasValidValue: ->
    @allowNull || @value?

  handleInputChange: (e) ->
    inputValue = @$(e.target).val()
    if inputValue != ''
      @value = inputValue
    else
      @value = null
    @trigger 'valueChanged', @