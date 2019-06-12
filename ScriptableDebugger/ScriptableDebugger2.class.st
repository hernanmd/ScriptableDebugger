"
Helpers:
- To execute a block multiple times:
	anInt timesRepeat: aBlock
	
Instance Variables:
- breakpoints: list of the breakpoints set by this scriptable debugger
- stepHooks: a list of blocks to be executed after each step. For example to signal a given exception if a condition is fulfilled (for example a given context no longer being on the stack)
	
Notes:
- by default, a DebugSession created by a ScriptableDebugger will be set NOT to trigger events to refresh graphical debuggers opened on it. So a graphical debugger opened on it will not refresh even when its buttons are pressed. See protocal ""graphical debugger"" for more info on this.
	
Ideas:
- protection against stepping into the ""Processor terminateActive"" of BlockClosure>>#newProcess.
-> Added to DebugSessionPlus>>#stepInto:, DebugSessionPlus>>#stepOver: and DebugSessionPlus>>#stepThrough:
"
Class {
	#name : #ScriptableDebugger2,
	#superclass : #Object,
	#instVars : [
		'process',
		'debugSession',
		'breakpoints',
		'stepHooks',
		'virtualBreakpoints'
	],
	#classVars : [
		'debuggerScripts'
	],
	#category : #ScriptableDebugger
}

{ #category : #start }
ScriptableDebugger2 class >> attachTo: aDebugSessionPlus [
	"Returns a new instance of ScriptableDebugger attached to aDebugSessionPlus"
	(aDebugSessionPlus class == DebugSessionPlus) ifFalse: [ Error signal: 'ScriptableDebugger can only attach to instances of DebugSessionPlus' ].
	^ self new attachTo: aDebugSessionPlus.

]

{ #category : #start }
ScriptableDebugger2 class >> debug: aBlock [
	"Creates an execution of aBlock and returns an instance of ScriptableDebugger attached to this execution"
	^ self new debug: aBlock

]

{ #category : #'debugger scripts' }
ScriptableDebugger2 class >> debuggerScripts [
	^ debuggerScripts
]

{ #category : #initialize }
ScriptableDebugger2 class >> initialize [
	debuggerScripts := Dictionary new.
]

{ #category : #'debugger scripts' }
ScriptableDebugger2 class >> registerDebuggerScript: aBlock underName: aSymbol [
	self debuggerScripts at: aSymbol put: aBlock.
]

{ #category : #'graphical debugger' }
ScriptableDebugger2 >> activateAutoRefreshOfAttachedGraphicalDebugger [
	debugSession activateEventTriggering.
	self refreshAttachedGraphicalDebugger.
]

{ #category : #'step hook' }
ScriptableDebugger2 >> addStepHook: aBlock [
	"Adds aBlock to the list of step hooks. Step hooks are executed after each step of the execution"
	stepHooks add: aBlock
]

{ #category : #querying }
ScriptableDebugger2 >> assignmentValue [
	"If the currentNode is an assignment node, returns the value of being assigned"
	(self currentNode isAssignment) ifFalse: [ Error signal: 'Not about to perform a assignment' ].
	^ self currentContext at: (self valueStackSizeOfContext: self currentContext).
]

{ #category : #querying }
ScriptableDebugger2 >> assignmentVariableName [
	"If the currentNode is an assignment node, returns the name of the variable being assigned a value"
	(self currentNode isAssignment) ifFalse: [ Error signal: 'Not about to perform a assignment' ].
	^ self currentNode variable name.
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> at: anInteger fromTheEndOfValueStackOfContext: aContext [
	"Returns the value at index <size of the value stack of aContext> - anInteger of the value stack of aContext"
	^ aContext at: ((self valueStackSizeOfContext: aContext) - anInteger).
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> at: anInteger ofValueStackOfContext: aContext [
	"Returns the value at index anInteger of the value stack of aContext"
	^ aContext at: anInteger.
]

{ #category : #start }
ScriptableDebugger2 >> attachTo: aDebugSessionPlus [
	"Attaches this scriptable debugger to an already existing instance of DebugSessionPlus"
	process := aDebugSessionPlus interruptedProcess.
	debugSession := aDebugSessionPlus.
	debugSession deactivateEventTriggering.
	^ self
]

{ #category : #accessing }
ScriptableDebugger2 >> breakpoints [
	"Returns the list of all breakpoints set by this scriptable debugger"
	^ breakpoints
]

{ #category : #helper }
ScriptableDebugger2 >> class: aClass isEqualOrSubclassOf: anotherClass [
	(aClass = anotherClass) ifTrue: [ ^ true ].
	^ anotherClass allSubclasses includes: aClass.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> commitVBreakpoints [
	"Sets actual breakpoints in the system at locations where this scriptable debugger has set virtual breakpoints. Empties the virtualBreakpoint collection of this scriptable debugger."
	virtualBreakpoints do: [ :vBrkpt | self setBreakpointOnASTNode: vBrkpt node ].
	virtualBreakpoints := OrderedCollection new.
]

{ #category : #stepping }
ScriptableDebugger2 >> completeExecution [
	"Runs the execution until the process itself is about to terminate. That's as far as you can safely step an execution without freezing the image."
	[process isTerminating] whileFalse: [ self step ]
]

{ #category : #stepping }
ScriptableDebugger2 >> completeTo: aContext [
	"Runs the execution until aContext is the top context"
	process completeTo: aContext
]

{ #category : #'querying - temporary variables' }
ScriptableDebugger2 >> context: aContext hasTemporaryNamed: aSymbol [
	^ aContext tempNames includes: aSymbol.
]

{ #category : #'querying - context property' }
ScriptableDebugger2 >> context: aContext isAboutToSend: aSymbol toAnInstanceOrSubInstanceOfClass: aClass [
	"Returns whether aContext is about to send a message of selector aSymbol to an object that is an instance of aClass, or an instance of one of its subclasses"
	| currentNode argumentNb receiverClass |
	currentNode := self currentNodeForContext: aContext.
	(currentNode isMessage) ifFalse: [ ^false ].
	(currentNode selector = aSymbol) ifFalse: [ ^false ].
	argumentNb := (currentNode arguments size).
	receiverClass := (self at: argumentNb fromTheEndOfValueStackOfContext: aContext) class.
	(receiverClass = aClass) ifTrue: [ ^true ].
	(aClass allSubclasses includes: receiverClass) ifTrue: [ ^true ].
	^ false.
]

{ #category : #'querying - context property' }
ScriptableDebugger2 >> context: aContext isForBlock: aBlock [
	"Returns whether aContext is a block context for aBlock"
	aContext isBlockContext ifFalse: [ ^ false ].
	^ aContext closure sourceNode == aBlock sourceNode.
]

{ #category : #'querying - context property' }
ScriptableDebugger2 >> contextIsAboutToSignalException: aContext [
	"Returns whether aContext is about to execute a message-send of selector #signal to an instance of the Exception class (or one of its subclasses)"
	| node |
	node := aContext method sourceNodeForPC: aContext pc.
	(node isMessage) ifFalse: [ ^false ].
	(node selector = #signal) ifFalse: [ ^false ].
	(aContext basicSize >= 1) ifFalse: [ ^false ].
	(Exception allSubclasses includes: (aContext at: (aContext basicSize))) ifTrue: [ ^true ]. "#signal sent to a subclass of Exception"
	(Exception allSubclasses includes: ((aContext at: (aContext basicSize)) class)) ifTrue: [ ^true ]. "#signal sent to an instance of a subclass of Exception"
	^ false
	
]

{ #category : #'querying - context stack' }
ScriptableDebugger2 >> contextIsOnStack: aContext [
	"Returns whether aContext is somewhere on the stack"
	^ (self findContextSuchThat: [ :aContexta| aContexta == aContext ]) isNotNil.
]

{ #category : #stepping }
ScriptableDebugger2 >> continue [
	"Steps the execution until it is about to signal an exception. If this exception is Halt or Break (i.e. a Breakpoint), skip the exception signal."
	| signalMessageNode exceptionClassBeingSignalled |
	self stepWhileFalse: [ self contextIsAboutToSignalException: self currentContext ].
	self isExecutionFinished ifTrue: [ ^self ].
	signalMessageNode := self currentNode.
	exceptionClassBeingSignalled := self currentContext at: ((self valueStackSizeOfContext: self currentContext) - signalMessageNode arguments size).
	(exceptionClassBeingSignalled == Halt) ifTrue: [ 
		"Encountered a Halt (typically signalled by a 'self halt')"
		self skip.
	].
	(exceptionClassBeingSignalled == Break) ifTrue: [ 
		"Encountered a Break (i.e. a breakpoint)"
		self skip.
	]
]

{ #category : #querying }
ScriptableDebugger2 >> currentContext [
	"Returns the context on top of the stack"
	^ debugSession interruptedContext.
]

{ #category : #querying }
ScriptableDebugger2 >> currentMethod [
	"Returns the method being executed by the current context."
	^ self currentContext method
]

{ #category : #querying }
ScriptableDebugger2 >> currentNode [
	"Returns the AST node about to be executed by the top context of the execution"
	^ self currentNodeForContext: self currentContext.
]

{ #category : #'querying - context property' }
ScriptableDebugger2 >> currentNodeForContext: aContext [
	"Returns the AST node aContext is about to execute"
	^ aContext method sourceNodeForPC: aContext pc.
]

{ #category : #querying }
ScriptableDebugger2 >> currentReceiver [
	"Returns the receiver of the current context"
	^ self currentContext receiver
]

{ #category : #querying }
ScriptableDebugger2 >> currentSelector [
	"Returns the selector of the method being executed by the current context."
	^ self currentContext method selector
]

{ #category : #'graphical debugger' }
ScriptableDebugger2 >> deactivateAutoRefreshOfAttachedGraphicalDebugger [
	debugSession deactivateEventTriggering.
]

{ #category : #start }
ScriptableDebugger2 >> debug: aBlock [
	| context |
	process := aBlock newProcess name: 'ScrptblDbgExec'.
	debugSession := DebugSessionPlus new
		name: 'ScrptblDbgDebugSession';
		process: process context: process suspendedContext.
	debugSession deactivateEventTriggering.
	debugSession stepInto; stepInto.
	^ self
]

{ #category : #accessing }
ScriptableDebugger2 >> debugSession [
	"Returns the DebugSession representing the execution this ScriptableDebugger is debugging"
	^ debugSession 
]

{ #category : #'debugger script' }
ScriptableDebugger2 >> executeDebuggerScriptNamed: aSymbol [
	"Executes the debugger script named aSymbol."
	(ScriptableDebugger2 debuggerScripts at: aSymbol ifAbsent: [ Error signal: ('No debugger script found with name: ', aSymbol) ]) new execute: self.
]

{ #category : #'debugger script' }
ScriptableDebugger2 >> executeDebuggerScriptNamed: aSymbol multipleTimes: anInteger [
	"Executes the debugger script named aSymbol as many times as anInteger"
	anInteger timesRepeat: [ self executeDebuggerScriptNamed: aSymbol ].
]

{ #category : #'debugger script' }
ScriptableDebugger2 >> executeDebuggerScriptNamed: aSymbol withArgs: anOrderedCollection [
	"Executes the debugger script named aSymbol, and giving it anOrderedCollection as argument."
	(ScriptableDebugger2 debuggerScripts at: aSymbol ifAbsent: [ Error signal: ('No debugger script found with name: ', aSymbol) ]) new execute: self withArgs: anOrderedCollection.
]

{ #category : #'debugger script' }
ScriptableDebugger2 >> executeDebuggerScriptNamed: aSymbol withArgs: anOrderedCollection multipleTimes: anInteger [
	"Executes the debugger script named aSymbol with arguments anOrderedCollection as many times as anInteger"
	anInteger timesRepeat: [ self executeDebuggerScriptNamed: aSymbol withArgs: anOrderedCollection ].
]

{ #category : #'querying - context stack' }
ScriptableDebugger2 >> findContextForSelector: aSymbol andClassOrSubclassOf: aClass [
	"Run through the context stack from top to bottom to find a context whose selector is aSymbol and for which the class of its receiver is equal to or a subclass of aClass"
	^ self findContextSuchThat: [ :ctxt | (ctxt method selector = aSymbol) and: [ self class: ctxt receiver class isEqualOrSubclassOf: aClass  ] ]
]

{ #category : #'querying - context stack' }
ScriptableDebugger2 >> findContextSuchThat: aBlock [
	"Run through the context stack from top to bottom to find a context for which aBlock evaluates to true. Returns the first such context found, or nil if none are found."
	^ self currentContext findContextSuchThat: aBlock
]

{ #category : #initialization }
ScriptableDebugger2 >> initialize [
	breakpoints := OrderedCollection new.
	stepHooks := OrderedCollection new.
	virtualBreakpoints := OrderedCollection new.
]

{ #category : #querying }
ScriptableDebugger2 >> isExecutionFinished [
	"Returns whether the debugged execution is finished"
	^ process isTerminating
]

{ #category : #querying }
ScriptableDebugger2 >> messageFirstArg [
	"If the currentNode is a message node with arguments, returns the value of its first argument"
	(self currentNode isMessage) ifFalse: [ Error signal: 'Not about to send a message' ].
	(self currentNode arguments size >= 1) ifFalse: [ Error signal: 'Message about to be sent does not have a first argument' ].
	^ self currentContext at: (self valueStackSizeOfContext: self currentContext) - (self currentNode arguments size) + 1.
]

{ #category : #querying }
ScriptableDebugger2 >> messageReceiver [
	"If the currentNode is a message node, returns the value of its receiver"
	(self currentNode isMessage) ifFalse: [ Error signal: 'Not about to send a message' ].
	^ self currentContext at: (self valueStackSizeOfContext: self currentContext) - (self currentNode arguments size).
]

{ #category : #querying }
ScriptableDebugger2 >> messageSecondArg [
	"If the currentNode is a message node with arguments, returns the value of its second argument"
	(self currentNode isMessage) ifFalse: [ Error signal: 'Not about to send a message' ].
	(self currentNode arguments size >= 2) ifFalse: [ Error signal: 'Message about to be sent does not have a second argument' ].
	^ self currentContext at: (self valueStackSizeOfContext: self currentContext) - (self currentNode arguments size) + 2.
]

{ #category : #querying }
ScriptableDebugger2 >> messageSelector [
	"If the currentNode is a message node, returns its selector"
	(self currentNode isMessage) ifFalse: [ Error signal: 'Not about to send a message' ].
	^ self currentNode selector.
]

{ #category : #querying }
ScriptableDebugger2 >> messageThirdArg [
	"If the currentNode is a message node with arguments, returns the value of its third argument"
	(self currentNode isMessage) ifFalse: [ Error signal: 'Not about to send a message' ].
	(self currentNode arguments size >= 3) ifFalse: [ Error signal: 'Message about to be sent does not have a third argument' ].
	^ self currentContext at: (self valueStackSizeOfContext: self currentContext) - (self currentNode arguments size) + 3.
]

{ #category : #'graphical debugger' }
ScriptableDebugger2 >> openInGraphicalDebugger [
	| specDbg |
	specDbg := SpecDebugger openOn: debugSession withFullView: true.
	specDbg terminateDebugSessionWhenClearing: false.
]

{ #category : #querying }
ScriptableDebugger2 >> pcOfContext: aContext [
	^ aContext pc
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> popFromValueStackOfContext: aContext [
	^ aContext pop
]

{ #category : #querying }
ScriptableDebugger2 >> previousContext [
	"Returns the context sender of the top context on the stack"
	^ self currentContext sender.
]

{ #category : #querying }
ScriptableDebugger2 >> previousMethod [
	"Returns the method being executed by the sender of the top context on the stack"
	^ self currentContext sender method.
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> push: aValue onValueStackOfContext: aContext [
	^ aContext push: aValue.
]

{ #category : #'graphical debugger' }
ScriptableDebugger2 >> refreshAttachedGraphicalDebugger [
	debugSession refreshAttachedDebugger.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> removeAllBreakpointsSetByMe [
	"Remove all the breakpoints set by self"
	breakpoints do: [ :breakpoint | breakpoint remove ].
]

{ #category : #breakpoints }
ScriptableDebugger2 >> removeAllVBreakpointsSetByMe [
	virtualBreakpoints := OrderedCollection new.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> removeBreakpointOnMethod: aCompiledMethod [
	"Remove all breakpoints set by this scriptable debugger on aCompiledMethod's method node (leaves breakpoints set on nodes inside aCompiledMethod)"
	| breakpointsToRemove |
	breakpointsToRemove := breakpoints select: [ :aBreakpoint | aBreakpoint node == aCompiledMethod ast ].
	breakpointsToRemove do: [:aBreakpoint | aBreakpoint remove].
]

{ #category : #'step hook' }
ScriptableDebugger2 >> removeStepHook: aBlock [
	"Remove aBlock from the list of step hooks"
	stepHooks remove: aBlock
]

{ #category : #breakpoints }
ScriptableDebugger2 >> runExecutionWhilePlacingBreakpointsWhen: aBlock [
	"Steps the execution until the end. After each step, evaluate aBlock. If true, sets a virtual breakpoint on the current node. After the execution is finished, commits all virtual breakpoints"
	| stepHook |
	stepHook := [ aBlock value ifTrue: [ self setVBreakpoint ] ].
	self addStepHook: stepHook.
	self stepWhileFalse: [ self isExecutionFinished ].
	self removeStepHook: stepHook.
	self commitVBreakpoints.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setBreakpointOnASTNode: anASTNode [
	"Sets a breakpoint on anASTNode"
	|b|
	b := Breakpoint new.
	b node: anASTNode.
	b always.
	b install.
	breakpoints add: b.
	^ b.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setBreakpointOnCurrentMethod [
	"Set a breakpoint on the method of the current context"
	|b|
	b := Breakpoint new.
	b node: (self currentContext method ast).
	b always.
	b install.
	breakpoints add: b.
	^ b.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setBreakpointOnMethod: aCompiledMethod [
	"Sets a breakpoint on a method"
	|b|
	b := Breakpoint new.
	b node: aCompiledMethod ast.
	b always.
	b install.
	breakpoints add: b.
	^ b.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setVBreakpoint [
	"Sets a virtual breakpoint on the current node"
	self setVBreakpointOnASTNode: self currentNode.
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setVBreakpointOnASTNode: aNode [
	virtualBreakpoints add: (VirtualBreakpoint newOnNode: aNode)
]

{ #category : #breakpoints }
ScriptableDebugger2 >> setVBreakpointOnMethod: aCompiledMethod [
	"Sets a virtual breakpoint on aCompiledMethod"
	virtualBreakpoints add: (VirtualBreakpoint newOnNode: aCompiledMethod ast)
]

{ #category : #stepping }
ScriptableDebugger2 >> skip [
	self skipWith: nil.
]

{ #category : #stepping }
ScriptableDebugger2 >> skipWith: replacementValue [
	"Skips the current message-send or assignment and use replacementValue as their return value instead"
	"If the current node is a message send or assignment"
	((self currentNode isMessage not) and: [ self currentNode isAssignment not]) ifTrue: [ ^false ].
	self currentNode isMessage ifTrue: [
		"Pop the arguments of the message send from the context's value stack"
		self currentNode arguments do: [ :arg | self currentContext pop ].
		"Pop the receiver from the context's value stack"
		self currentContext pop.
		"Push the replacement value on the context's value stack, to simulate that the message send happened and returned nil"
		self currentContext push: replacementValue.
		"Increase the pc to go over the message send"
		self currentContext pc: self currentContext pc + 1.
		"Execute bytecodes the debugger usually executes without stopping the execution (for example popping the return value of the just executed message send if it is not used afterwards)"
		self debugSession stepToFirstInterestingBytecodeIn: self debugSession interruptedProcess.
		^ self.
	].
	self currentNode isAssignment ifTrue: [
		"Pop the value to be assigned"
		self currentContext pop.
		"Push the replacement value on the context's value stack, to simulate that the assignment happened and had value nil"
		self currentContext push: replacementValue.
		"Increase the pc to go over the assignment"
		self currentContext pc: self currentContext pc + 2.
		"Execute bytecodes the debugger usually executes without stopping the execution (for example popping the return value of the just executed message send if it is not used afterwards)"
		self debugSession stepToFirstInterestingBytecodeIn: self debugSession interruptedProcess.
		^ self.
	].
]

{ #category : #stepping }
ScriptableDebugger2 >> step [
	"Step the execution once"
	debugSession stepInto.
	stepHooks do: [ :aBlock | aBlock value ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepOver [
	|startContext|
	startContext := self currentContext.
	self step.
	[ (self currentContext == startContext) or: [ startContext hasSender: self currentContext ] ] whileFalse: [ self step. ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepThrough [
	debugSession stepThrough.
]

{ #category : #stepping }
ScriptableDebugger2 >> stepToContext: aContext [
	"Runs the execution until aContext is the top context"
	self stepWhileFalse: [ self currentContext == aContext ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepToContextForBlock: aBlock [
	"Runs the execution until the current context is a block context for aBlock"
	self stepWhileFalse: [ self context: (self currentContext) isForBlock: aBlock ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepToNextBreakpointOrHalt [
	"Step the execution until a breakpoint or halt is reached. Skips the breakpoint/halt so that no exception is signalled"
	self stepWhileFalse: [
		(self currentNode isMessage) and: [ (self currentNode selector = #signal) and: [(self currentReceiver = Halt) or: [self currentReceiver = Break]  ]]].
	"If the execution is not finished, it means the stepping stopped because it was about to signal a Halt or Break. In this case, skip the signal message-send "
	self isExecutionFinished ifFalse: [ self skip ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepUntil: aBlock [
	"Steps the execution until aBlock evaluates to true"
	aBlock whileFalse: [ self step ]
]

{ #category : #stepping }
ScriptableDebugger2 >> stepWhileFalse: aBlock [
	"Steps the execution while aBlock evaluates to false. The loop stops if it would step while the execution's process is terminating"
	self stepWhileTrue: [ aBlock value not ].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepWhileFalse: aBlock andContextOnStack: aContext [
	"Steps the execution while aBlock evaluates to false AND aContext is on the stack. The loop stops if it would step while the execution's process is terminating"
	self stepWhileTrue: [ aBlock value not and: [self contextIsOnStack: aContext]].
]

{ #category : #stepping }
ScriptableDebugger2 >> stepWhileTrue: aBlock [
	"Steps the execution while aBlock evaluates to false. Stops the loop if it would step while the execution's process is terminating"
	[[aBlock value] whileTrue: [ self step ]] on: SteppingATerminatingProcess do: [ ^ self. ]
]

{ #category : #stepping }
ScriptableDebugger2 >> stepWhileTrue: aBlock andContextOnStack: aContext [
	"Steps the execution while aBlock evaluates to true AND aContext is on the stack. The loop stops if it would step while the execution's process is terminating"
	self stepWhileTrue: [ aBlock value and: [self contextIsOnStack: aContext]].
]

{ #category : #'querying - temporary variables' }
ScriptableDebugger2 >> temporaryNamed: aSymbol ofContext: aContext [
	^ aContext tempNamed: aSymbol
]

{ #category : #'querying - temporary variables' }
ScriptableDebugger2 >> temporaryNamed: aSymbol ofContext: aContext put: aValue [
	^ aContext tempNamed: aSymbol put: aValue.
]

{ #category : #'querying - temporary variables' }
ScriptableDebugger2 >> temporaryNamesOfContext: aContext [
	^ aContext tempNames
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> topValueOfCurrentContextValueStack [
	"Returns the value on the top of the value stack of the current context"
	^ self at: 0 fromTheEndOfValueStackOfContext: self currentContext.
]

{ #category : #contextValueStack }
ScriptableDebugger2 >> valueStackSizeOfContext: aContext [
	"Returns the size of the value stack of aContext"
	^ aContext basicSize
]