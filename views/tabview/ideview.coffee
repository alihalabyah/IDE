class IDE.IDEView extends IDE.WorkspaceTabView

  constructor: (options = {}, data) ->

    options.tabViewClass     = AceApplicationTabView
    options.createNewEditor ?= yes

    super options, data

    @openFiles = []
    @bindListeners()

  bindListeners: ->
    @on 'PlusHandleClicked', @bound 'createPlusContextMenu'

    @tabView.on 'MachineTerminalRequested', @bound 'openMachineTerminal'
    @tabView.on 'MachineWebPageRequested',  @bound 'openMachineWebPage'
    @tabView.on 'ShortcutsViewRequested',   @bound 'createShortcutsView'
    @tabView.on 'TerminalPaneRequested',    @bound 'createTerminal'
    #absolete: 'preview file' feature was removed (bug #82710798)
    @tabView.on 'PreviewPaneRequested',     (url) -> window.open "http://#{url}"
    @tabView.on 'DrawingPaneRequested',     @bound 'createDrawingBoard'
    @tabView.on 'ViewNeedsToBeShown',       @bound 'showView'
    @tabView.on 'TabNeedsToBeClosed',       @bound 'closeTabByFile'
    @tabView.on 'GoToLineRequested',        @bound 'goToLine'

    @tabView.on 'FileNeedsToBeOpened', (file, contents, callback) =>
      @closeUntitledFileIfNotChanged()
      @openFile file, contents, callback

    @tabView.on 'PaneDidShow', =>
      @updateStatusBar()
      @focusTab()

    @once 'viewAppended', => KD.utils.wait 300, =>
      @createEditor()  if @getOption 'createNewEditor'

    @tabView.on 'PaneAdded', (pane) =>
      return unless pane.options.editor
      {tabHandle} = pane

      icon = new KDCustomHTMLView
        tagName  : 'span'
        cssClass : 'options'
        click    : => @createEditorMenu tabHandle, icon

      tabHandle.addSubView icon, null, yes

  createPane_: (view, paneOptions, paneData) ->
    unless view or paneOptions
      return new Error 'Missing argument for createPane_ helper'

    unless view instanceof KDView
      return new Error 'View must be an instance of KDView'

    pane = new KDTabPaneView paneOptions, paneData
    pane.addSubView view
    pane.view = view
    @tabView.addPane pane

    pane.once 'KDObjectWillBeDestroyed', => @handlePaneRemoved pane

    return pane

  createEditor: (file, content, callback = noop) ->
    file        = file    or FSHelper.createFileInstance path: @getDummyFilePath()
    content     = content or ''
    editorPane  = new IDE.EditorPane { file, content, delegate: this }
    paneOptions =
      name      : file.name
      editor    : editorPane
      aceView   : editorPane.aceView # this is required for ace app. see AceApplicationTabView:6

    editorPane.once 'EditorIsReady', ->
      {ace}      = editorPane.aceView
      appManager = KD.getSingleton 'appManager'

      ace.on 'ace.change.cursor', (cursor) ->
        appManager.tell 'IDE', 'updateStatusBar', 'editor', { file, cursor }

      ace.on 'FindAndReplaceViewRequested', (withReplaceMode) ->
        appManager.tell 'IDE', 'showFindReplaceView', withReplaceMode

      ace.editor.scrollToRow 0
      editorPane.goToLine 1

      callback editorPane

    @createPane_ editorPane, paneOptions, file

  createShortcutsView: ->
    @createPane_ new IDE.ShortcutsView, { name: 'Shortcuts' }

  createTerminal: (machine, path, session) ->

    {appManager} = KD.singletons

    frontApp = appManager.getFrontApp()
    machine ?= frontApp.mountedMachine
    path    ?= frontApp.workspaceData?.rootPath

    terminalPane = new IDE.TerminalPane { machine, path, session }
    @createPane_ terminalPane, { name: 'Terminal' }

    terminalPane.once 'WebtermCreated', =>
      terminalPane.webtermView.on 'click', @bound 'click'

  createDrawingBoard: ->
    @createPane_ new IDE.DrawingPane, { name: 'Drawing' }

  createPreview: (url) ->
    previewPane = new IDE.PreviewPane { url }
    @createPane_ previewPane, { name: 'Browser' }

    previewPane.on 'LocationChanged', (newLocation) =>
      @updateStatusBar 'preview', newLocation

  showView: (view) ->
    @createPane_ view, { name: 'Search Result' }

  updateStatusBar: (paneType, data) ->
    appManager = KD.getSingleton 'appManager'

    unless paneType
      subView  = @getActivePaneView()
      paneType = subView.getOptions().paneType  if subView

    unless data
      if paneType is 'editor'
        {file} = subView.getOptions()
        {ace}  = subView.aceView
        cursor = if ace.editor? then ace.editor.getCursorPosition() else row: 0, column: 0
        data   = { file, cursor }

      else if paneType is 'terminal'
        machineName = subView.machine.getName()
        data   = { machineName }

      else if paneType is 'preview'
        data   = subView.getOptions().url or 'Enter a URL to browse...'

      else if paneType is 'drawing'
        data   = 'Use this panel to draw something'

      else if paneType is 'searchResult'
        {stats, searchText} = subView.getOptions()
        data = { stats, searchText }

    appManager.tell 'IDE', 'updateStatusBar', paneType, data

  removeOpenDocument: ->
    # TODO: This method is legacy, should be reimplemented in ace bundle.

  getActivePaneView: ->
    return @tabView.getActivePane().view

  focusTab: ->
    pane = @getActivePaneView()
    return unless pane

    KD.utils.defer ->
      {paneType} = pane.getOptions()
      appManager = KD.getSingleton 'appManager'

      pane.setFocus? yes

      if paneType is 'editor'
        appManager.tell 'IDE', 'setFindAndReplaceViewDelegate'
        appManager.tell 'IDE', 'showFindAndReplaceViewIfNecessary'
      else
        appManager.tell 'IDE', 'hideFindAndReplaceView'

  goToLine: ->
    @getActivePaneView().aceView.ace.showGotoLine()

  click: ->
    super

    appManager = KD.getSingleton 'appManager'

    appManager.tell 'IDE', 'setActiveTabView', @tabView
    appManager.tell 'IDE', 'setFindAndReplaceViewDelegate'
    
    
  openSavedFile: (file, content) ->
      
      pane = @tabView.getActivePane()
      if pane.data instanceof FSFile and pane.data.path is @getDummyFilePath()
        @tabView.removePane @tabView.getActivePane()
      @openFile file, content


  openFile: (file, content, callback = noop) ->
    if @openFiles.indexOf(file) > -1
      editorPane = @switchToEditorTabByFile file
      callback editorPane
    else
      @createEditor file, content, callback
      @openFiles.push file

  switchToEditorTabByFile: (file) ->
    for pane, index in @tabView.panes when file is pane.getData()
      @tabView.showPaneByIndex index
      return editorPane = pane.view

  toggleFullscreen: ->
    @toggleClass 'fullscren'
    KD.getSingleton('windowController').notifyWindowResizeListeners()
    @isFullScreen = !@isFullScreen

  handlePaneRemoved: (pane) ->
    file = pane.getData()
    @openFiles.splice @openFiles.indexOf(file), 1
    @emit 'PaneRemoved'

  getDummyFilePath: ->
    return 'localfile:/Untitled.txt'

  openMachineTerminal: (machine) ->
    @createTerminal machine

  openMachineWebPage: (machine) ->
    @createPreview machine.ipAddress

  closeTabByFile: (file)  ->
    for pane in @tabView.panes when pane?.data is file
      pane.getOptions().aceView.ace.contentChanged = no # hook to avoid file close modal
      @tabView.removePane pane

  closeUntitledFileIfNotChanged: ->
    for pane in @tabView.panes when pane
      if pane.data instanceof FSFile and pane.data.path is @getDummyFilePath()
        if pane.view.getValue() is ''
          @tabView.removePane pane

  getPlusMenuItems: ->

    {appManager} = KD.singletons

    frontApp = appManager.getFrontApp()
    machine  = frontApp.mountedMachine

    sessions = machine?.getBaseKite().terminalSessions or []

    terminalSessions =
      "New Session"  :
        callback     : => @createTerminal machine
        separator    : sessions.length > 0

    activeSessions = []
    frontApp.forEachSubViewInIDEViews_ 'terminal', (pane) =>
      if pane.remote?
        activeSessions.push pane.remote.session

    sessions.forEach (session, i) =>
      isActive = session in activeSessions
      terminalSessions["Session (#{session[0..5]}) &nbsp"] =
        disabled          : isActive
        children          :
          'Open'          :
            disabled      : isActive
            callback      : => @createTerminal machine, null, session
          'Terminate'     :
            callback      : => @terminateSession machine, session

    items =
      'New File'          : callback : => @createEditor()
      'New Terminal'      : children : terminalSessions
      # 'New Browser'       : callback : => @createPreview()
      'New Drawing Board' :
        callback          : => @createDrawingBoard()
        separator         : yes
      'Split Vertically':
        callback          : ->
          appManager.getFrontApp().splitVertically()
      'Split Horizontally':
        callback          : ->
          appManager.getFrontApp().splitHorizontally()

    if @parent instanceof KDSplitViewPanel
      items['Undo Split'] =
        separator         : yes
        callback          : ->
          appManager.getFrontApp().mergeSplitView()
    else
      items['']           = # TODO: `type: 'separator'` also creates label, see: https://cloudup.com/c90pFQS_n6X
        type              : 'separator'

    label                 = if @isFullScreen then 'Exit Fullscreen' else 'Enter Fullscreen'
    items[label]          =
      callback            : @bound 'toggleFullscreen'

    return items

  createEditorMenu: (tabHandle, icon) ->
    tabHandle.setClass 'menu-visible'
    KD.getSingleton('appManager').tell 'IDE', 'showStatusBarMenu', this, icon

    KD.utils.defer =>
      @menu.once 'KDObjectWillBeDestroyed', =>
        tabHandle.unsetClass 'menu-visible'
        delete @menu

  createPlusContextMenu: ->

    offset      = @holderView.plusHandle.$().offset()
    offsetLeft  = offset.left - 133
    margin      = if offsetLeft >= -1 then -20 else 12
    placement   = 'top'
    options     =
      delegate  : this
      x         : Math.max 0, offsetLeft
      y         : offset.top + 30
      arrow     : { placement, margin }

    contextMenu = new KDContextMenu options, @getPlusMenuItems()

    contextMenu.once 'ContextMenuItemReceivedClick', -> contextMenu.destroy()




  terminateSession: (machine, session)->

    machine.getBaseKite().webtermKillSession {session}

    .catch (err)->
      warn "Failed to terminate session, possibly it's already dead.", err
