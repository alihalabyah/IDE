class IDE.TerminalPane extends IDE.Pane

  constructor: (options = {}, data) ->

    options.cssClass  = 'terminal-pane terminal'
    options.paneType  = 'terminal'
    options.readOnly ?= no

    super options, data

    {@machine, @session} = @getOptions()

    @createTerminal()


  createTerminal: ->
    @webtermView       = new WebTermView
      delegate         : this
      readOnly         : @getOption 'readOnly'
      machine          : @machine
      mode             : @getMode()
      session          : @session
      cssClass         : 'webterm'
      advancedSettings : no

    @addSubView @webtermView

    @webtermView.on 'WebTermConnected', (remote) =>
      @remote = remote
      @emit 'WebtermCreated'

      KD.utils.wait 166, =>
        {path} = @getOptions()
        @runCommand "cd #{path}" if path

    @webtermView.connectToTerminal()

    @webtermView.once "WebTerm.terminated", =>

      return  unless @parent

      paneView = @parent
      tabView  = paneView.parent

      tabView.removePane paneView

      @machine.getBaseKite().fetchTerminalSessions()


  getMode: ->
    return  if @session? then 'resume' else 'create'

  runCommand: (command, callback) ->
    return unless command

    unless @remote
      return new Error 'Could not execute your command, remote is not created'

    if callback
      @webtermView.once 'WebTermEvent', callback
      command += ';echo $?|kdevent'

    @remote.input "#{command}\n"

  notify: (message) -> console.log 'notify:', message

  resurrect: ->
    @destroySubViews()
    @createTerminal()

  setFocus: (state) ->
    super state
    @webtermView.setFocus state
