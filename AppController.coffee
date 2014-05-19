class IDEAppController extends AppController

  KD.registerAppClass this,
    name         : "IDE"
    route        : "/:name?/IDE"
    behavior     : "application"
    preCondition :
      condition  : (options, cb)-> cb KD.isLoggedIn()
      failure    : (options, cb)->
        KD.singletons.appManager.open 'IDE', conditionPassed : yes
        KD.showEnforceLoginModal()

  constructor: (options = {}, data) ->
    options.appInfo =
      type          : "application"
      name          : "IDE"

    super options, data

    layoutOptions       =
      direction         : "vertical"
      splitName         : "BaseSplit"
      sizes             : [ null, "250px" ]
      views             : [
        {
          type          : "split"
          options       :
            direction   : "vertical"
            sizes       : [ "250px", null]
          views         : [
            {
              type      : "custom"
              name      : "filesPane"
              paneClass : IDEFilesTabView
            },
            {
              type      : "custom"
              name      : "editorPane"
              paneClass : IDETabView
            }
          ]
        },
        {
          type          : "custom"
          name          : "socialsPane"
          paneClass     : IDESocialsTabView
        }
      ]

    workspace = new Workspace { layoutOptions }
    workspace.once "ready", => @getView().addSubView workspace.getView()
