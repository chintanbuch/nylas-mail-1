React = require 'react'
_ = require 'underscore'
EmailFrame = require('./email-frame').default
{encodedAttributeForFile} = require('./inline-image-listeners')
{
  DraftHelpers,
  CanvasUtils,
  NylasAPI,
  NylasAPIRequest,
  MessageUtils,
  MessageBodyProcessor,
  QuotedHTMLTransformer,
  FileDownloadStore
} = require 'nylas-exports'
{
  InjectedComponentSet,
  RetinaImg
} = require 'nylas-component-kit'

TransparentPixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNikAQAACIAHF/uBd8AAAAASUVORK5CYII="

class MessageItemBody extends React.Component
  @displayName: 'MessageItemBody'
  @propTypes:
    message: React.PropTypes.object.isRequired
    downloads: React.PropTypes.object.isRequired

  constructor: (@props) ->
    @_mounted = false
    @state =
      showQuotedText: DraftHelpers.isForwardedMessage(@props.message)
      processedBody: null

  componentWillMount: =>
    @_unsub = MessageBodyProcessor.subscribe @props.message, (processedBody) =>
      @setState({processedBody})

  componentDidMount: =>
    @_mounted = true

  componentWillReceiveProps: (nextProps) ->
    if nextProps.message.id isnt @props.message.id
      @_unsub?()
      @_unsub = MessageBodyProcessor.subscribe nextProps.message, (processedBody) =>
        @setState({processedBody})

  componentWillUnmount: =>
    @_mounted = false
    @_unsub?()

  render: =>
    <span>
      <InjectedComponentSet
        matching={role: "message:BodyHeader"}
        exposedProps={message: @props.message}
        direction="column"
        style={width:'100%'}/>
      {@_renderBody()}
      {@_renderQuotedTextControl()}
    </span>

  _renderBody: =>
    if _.isString(@props.message.body) and _.isString(@state.processedBody)
      <EmailFrame
        showQuotedText={@state.showQuotedText}
        content={@_mergeBodyWithFiles(@state.processedBody)}
        message={@props.message}
      />
    else
      <div className="message-body-loading">
        <RetinaImg
          name="inline-loading-spinner.gif"
          mode={RetinaImg.Mode.ContentDark}
          style={{width: 14, height: 14}}/>
      </div>

  _renderQuotedTextControl: =>
    return null unless QuotedHTMLTransformer.hasQuotedHTML(@props.message.body)
    <a className="quoted-text-control" onClick={@_toggleQuotedText}>
      <span className="dots">&bull;&bull;&bull;</span>
    </a>

  _toggleQuotedText: =>
    @setState
      showQuotedText: !@state.showQuotedText

  _mergeBodyWithFiles: (body) =>
    # Replace cid: references with the paths to downloaded files
    for file in @props.message.files
      download = @props.downloads[file.id]

      # Note: I don't like doing this with RegExp before the body is inserted into
      # the DOM, but we want to avoid "could not load cid://" in the console.

      if download and download.state isnt 'finished'
        inlineImgRegexp = new RegExp("<\s*img.*src=['\"]cid:#{file.contentId}['\"][^>]*>", 'gi')
        # Render a spinner
        body = body.replace inlineImgRegexp, =>
          '<img alt="spinner.gif" src="nylas://message-list/assets/spinner.gif" style="-webkit-user-drag: none;">'
      else
        # Render the completed download. We include data-nylas-file so that if the image fails
        # to load, we can parse the file out and call `Actions.fetchFile` to retrieve it.
        # (Necessary when attachment download mode is set to "manual")
        cidRegexp = new RegExp("cid:#{file.contentId}(['\"])", 'gi')
        body = body.replace cidRegexp, (text, quoteCharacter) ->
          "file://#{FileDownloadStore.pathForFile(file)}#{quoteCharacter} data-nylas-file=\"#{encodedAttributeForFile(file)}\" "

    # Replace remaining cid: references - we will not display them since they'll
    # throw "unknown ERR_UNKNOWN_URL_SCHEME". Show a transparent pixel so that there's
    # no "missing image" region shown, just a space.
    body = body.replace(MessageUtils.cidRegex, "src=\"#{TransparentPixel}\"")

    return body

module.exports = MessageItemBody
