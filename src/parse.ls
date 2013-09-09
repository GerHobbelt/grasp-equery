require! acorn
{alias-map, matches-map, matches-alias-map, literal-map} = require 'grasp-syntax-javascript'
{get-node-at-path} = require './common'

function parse selector
  attempts =
    * code: selector
      path: []
    * code: "function f(){ #selector; }"
      path: ['body' 'body' 0]
    * code: "while (true) { #selector; }"
      path: ['body' 'body' 0]
    * code: "switch (x) { #selector }"
      path: ['cases' 0]
    * code: "try { } #selector"
      path: ['handlers' 0]
  for {code}:attempt in attempts
    try
      parsed-selector = acorn.parse code
      path = attempt.path
      break
    catch
      continue
  throw new Error "Error processing selector '#selector'." unless parsed-selector

  selector-body = parsed-selector.body
  throw new Error "Selector body can't be more than one statement" if selector-body.length > 1 # ?? TODO
  extracted-selector = get-node-at-path selector-body.0, path
  final-selector = if extracted-selector.type is 'ExpressionStatement'
                   then extracted-selector.expression
                   else extracted-selector
  root = type: 'Root', value: final-selector
  process-selector root
  root.value

!function process-selector ast
  delete ast.start
  delete ast.end
  for key, node of ast when key isnt 'type'
    if typeof! node is 'Array'
      for n, i in node
        if process-node n
          node[i] = that
        else
          process-selector n
    else if typeof! node is 'Object'
      if process-node node
        ast[key] = that
      else
        process-selector node

function process-node node
  node-type = node.type

  if node-type is 'Identifier'
    name = node.name
    if name is '_'
      null
    else if name is '__'
      type: 'Grasp'
      grasp-type: 'wildcard'
    else if name is '_$'
      type: 'Grasp'
      grasp-type: 'array-wildcard'
    else if /^_([_a-zA-Z]+)/.exec name
      ident = that.1.replace /_/, '-'

      if ident of matches-map or ident of matches-alias-map
        type: 'Grasp'
        grasp-type: 'matches'
        value: matches-map[matches-alias-map[ident] or ident]
      else if ident of literal-map
        type: 'Grasp'
        grasp-type: 'literal'
        value: literal-map[ident]
      else
        type: 'Grasp'
        grasp-type: 'node-type'
        value: alias-map[ident] or ident
  else if node-type is 'MemberExpression'
    return unless node.computed

    attrs = []
    n = node
    while n.type is 'MemberExpression'
      return unless n.computed
      attrs.unshift n.property
      n = n.object
    return unless n.type is 'Identifier'

    ident = process-node n
    return unless ident

    processed-attrs = []
    for attr in attrs
      if process-attr attr
        processed-attrs.push that
      else
        return

    type: 'Grasp'
    grasp-type: 'compound'
    ident: ident
    attrs: processed-attrs
  else if node-type is 'ExpressionStatement'
    process-node node.expression

function process-attr attr
  attr-type = attr.type

  if attr-type is 'Identifier'
    path: [attr.name]
  else if attr-type is 'MemberExpression'
    path = get-member-path attr
    return unless path

    path: path
  else if attr-type in <[ AssignmentExpression BinaryExpression ]> and attr.operator in <[ = != ]>
    path = get-member-path attr.left
    return unless path

    path: path
    op: attr.operator
    value: attr.right

function get-member-path node
  path = []
  while node.type is 'MemberExpression'
    return if node.computed
    path.unshift node.property.name
    node = node.object
  path.unshift node.name
  path

module.exports = {parse}
