package formatter.marker;

import formatter.config.SameLineConfig;
import formatter.config.WhitespaceConfig;

class MarkSameLine {
	public static function markSameLine(parsedCode:ParsedCode, configSameLine:SameLineConfig, configWhitespace:WhitespaceConfig) {
		markAnonObjectsTypedefsSameLine(parsedCode, configSameLine, configWhitespace);
		markDollarSameLine(parsedCode, configSameLine, configWhitespace);

		parsedCode.root.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			switch (token.tok) {
				case Kwd(KwdIf):
					markIf(token, parsedCode, configSameLine);
				case Kwd(KwdElse):
					markElse(token, parsedCode, configSameLine);
				case Kwd(KwdFor):
					markFor(token, parsedCode, configSameLine);
				case Kwd(KwdWhile):
					if ((token.parent != null) && (token.parent.is(Kwd(KwdDo)))) {
						applySameLinePolicy(token, parsedCode, configSameLine.doWhileBody);
						return GO_DEEPER;
					}
					markBodyAfterPOpen(token, parsedCode, configSameLine.whileBody, false);
				case Kwd(KwdDo):
					markBody(token, parsedCode, configSameLine.doWhileBody, false);
				case Kwd(KwdTry):
					markBody(token, parsedCode, configSameLine.tryBody, false);
				case Kwd(KwdCatch):
					markBodyAfterPOpen(token, parsedCode, configSameLine.catchBody, false);
					applySameLinePolicyChained(token, parsedCode, configSameLine.tryBody, configSameLine.tryCatch);
				case Kwd(KwdCase):
					markCase(token, parsedCode, configSameLine);
				case Kwd(KwdDefault):
					markCase(token, parsedCode, configSameLine);
				case Kwd(KwdFunction):
					markFunction(token, parsedCode, configSameLine);
				default:
			}
			return GO_DEEPER;
		});
	}

	static function shouldIfBeSameLine(token:TokenTree):Bool {
		if (token == null) {
			return false;
		}
		if (!token.is(Kwd(KwdIf))) {
			return false;
		}
		var parent:TokenTree = token.parent;
		if (parent.tok == null) {
			return false;
		}
		switch (parent.tok) {
			case Kwd(KwdReturn):
				return true;
			case Binop(OpAssign):
				return true;
			case POpen:
				var pos:Position = parent.getPos();
				if ((pos.min < token.pos.min) && (pos.max > token.pos.max)) {
					return true;
				}
			case Kwd(KwdElse):
				return shouldElseBeSameLine(parent);
			case DblDot:
				return isReturnExpression(parent);
			default:
		}
		return false;
	}

	static function isReturnExpression(token:TokenTree):Bool {
		var parent:TokenTree = token;
		while (parent.parent.tok != null) {
			parent = parent.parent;
			switch (parent.tok) {
				case Kwd(KwdReturn):
					return true;
				case Kwd(KwdFunction):
					return false;
				case BkOpen:
					return false;
				case Binop(OpAssign):
					return true;
				default:
			}
		}
		return false;
	}

	static function shouldElseBeSameLine(token:TokenTree):Bool {
		if (token == null) {
			return false;
		}
		if (!token.is(Kwd(KwdElse))) {
			return false;
		}
		return shouldIfBeSameLine(token.parent);
	}

	static function markIf(token:TokenTree, parsedCode:ParsedCode, configSameLine:SameLineConfig) {
		if (shouldIfBeSameLine(token) && configSameLine.expressionIf == Same) {
			markBodyAfterPOpen(token, parsedCode, Same, configSameLine.expressionIfWithBlocks);
			return;
		}

		markBodyAfterPOpen(token, parsedCode, configSameLine.ifBody, false);
		var prev:TokenInfo = parsedCode.tokenList.getPreviousToken(token);
		if ((prev != null) && (prev.token.is(Kwd(KwdElse)))) {
			applySameLinePolicy(token, parsedCode, configSameLine.elseIf);
		}
	}

	static function markElse(token:TokenTree, parsedCode:ParsedCode, configSameLine:SameLineConfig) {
		if (shouldElseBeSameLine(token) && configSameLine.expressionIf == Same) {
			markBody(token, parsedCode, Same, configSameLine.expressionIfWithBlocks);
			var prev:TokenInfo = parsedCode.tokenList.getPreviousToken(token);
			if (prev == null) {
				return;
			}
			if (prev.token.is(BrClose)) {
				applySameLinePolicyChained(token, parsedCode, configSameLine.ifBody, configSameLine.ifElse);
			}
			return;
		}

		markBody(token, parsedCode, configSameLine.elseBody, false);
		applySameLinePolicyChained(token, parsedCode, configSameLine.ifBody, configSameLine.ifElse);
	}

	static function markCase(token:TokenTree, parsedCode:ParsedCode, config:SameLineConfig) {
		if (token == null) {
			return;
		}
		var dblDot:TokenTree = token.access().firstOf(DblDot).token;
		if (dblDot == null) {
			return;
		}
		if (isReturnExpression(token) && (config.expressionCase == Same)) {
			parsedCode.tokenList.noLineEndAfter(dblDot);
			return;
		}
		if (config.caseBody != Same) {
			return;
		}
		if ((dblDot.children != null) && (dblDot.children.length == 1)) {
			parsedCode.tokenList.noLineEndAfter(dblDot);
		}
	}

	static function markFor(token:TokenTree, parsedCode:ParsedCode, configSameLine:SameLineConfig) {
		if (token == null) {
			return;
		}
		var parent:TokenTree = token.parent;
		if ((parent == null) || (parent.tok == null)) {
			return;
		}
		switch (parent.tok) {
			case BkOpen:
				if (configSameLine.comprehensionFor == Same) {
					markBodyAfterPOpen(token, parsedCode, configSameLine.comprehensionFor, false);
					return;
				}
			default:
		}
		markBodyAfterPOpen(token, parsedCode, configSameLine.forBody, false);
	}

	static function markBodyAfterPOpen(token:TokenTree, parsedCode:ParsedCode, policy:SameLinePolicy, includeBrOpen:Bool) {
		var body:TokenTree = token.access().firstOf(POpen).nextSibling().token;
		while (body != null) {
			switch (body.tok) {
				case BrOpen:
					if (includeBrOpen) {
						markBlockBody(body, parsedCode, policy);
					}
					return;
				case CommentLine(_):
					var prev:TokenInfo = parsedCode.tokenList.getPreviousToken(body);
					if (prev != null) {
						if (!parsedCode.isOriginalSameLine(body, prev.token)) {
							applySameLinePolicy(body, parsedCode, policy);
							return;
						}
					}
					body = body.nextSibling;
				default:
					break;
			}
		}
		if (body == null) {
			return;
		}

		applySameLinePolicy(body, parsedCode, policy);
	}

	static function markBody(token:TokenTree, parsedCode:ParsedCode, policy:SameLinePolicy, includeBrOpen:Bool) {
		var body:TokenTree = token.access().firstChild().token;
		if (body == null) {
			return;
		}
		if (body.is(BrOpen)) {
			if (includeBrOpen) {
				markBlockBody(body, parsedCode, policy);
			}
			return;
		}
		applySameLinePolicy(body, parsedCode, policy);
	}

	static function markBlockBody(token:TokenTree, parsedCode:ParsedCode, policy:SameLinePolicy) {
		if (token == null) {
			return;
		}
		if (!token.is(BrOpen)) {
			return;
		}
		if ((token.children == null) || (token.children.length > 2)) {
			return;
		}
		parsedCode.tokenList.noLineEndAfter(token);
		for (child in token.children) {
			switch (child.tok) {
				case BrClose:
					var next:TokenInfo = parsedCode.tokenList.getNextToken(child);
					switch (next.token.tok) {
						case Kwd(KwdElse):
							parsedCode.tokenList.noLineEndAfter(child);
						case Kwd(KwdCatch):
							parsedCode.tokenList.noLineEndAfter(child);
						case Semicolon:
							parsedCode.tokenList.whitespace(child, NoneAfter);
						case Comma:
							parsedCode.tokenList.whitespace(child, NoneAfter);
						default:
							continue;
					}
				default:
					var lastToken:TokenTree = MarkLineEnds.lastToken(child);
					if (lastToken == null) {
						return;
					}
					parsedCode.tokenList.noLineEndAfter(lastToken);
			}
		}
	}

	static function applySameLinePolicyChained(token:TokenTree, parsedCode:ParsedCode, previousBlockPolicy:SameLinePolicy, policy:SameLinePolicy) {
		if (policy == Same) {
			var prev:TokenInfo = parsedCode.tokenList.getPreviousToken(token);
			if (prev == null) {
				policy = Next;
			}
			if ((!prev.token.is(BrClose)) && (previousBlockPolicy != Same)) {
				policy = Next;
			}
		}
		applySameLinePolicy(token, parsedCode, policy);
	}

	static function applySameLinePolicy(token:TokenTree, parsedCode:ParsedCode, policy:SameLinePolicy) {
		switch (policy) {
			case Same:
				parsedCode.tokenList.wrapBefore(token, true);
				parsedCode.tokenList.noLineEndBefore(token);
				var lastToken:TokenTree = MarkLineEnds.lastToken(token);
				if (lastToken == null) {
					return;
				}
				var next:TokenInfo = parsedCode.tokenList.getNextToken(lastToken);
				if (next == null) {
					return;
				}
				switch (next.token.tok) {
					case Kwd(KwdElse):
						parsedCode.tokenList.noLineEndAfter(lastToken);
					default:
				}
				return;
			case Next:
				parsedCode.tokenList.lineEndBefore(token);
		}
	}

	static function markAnonObjectsTypedefsSameLine(parsedCode:ParsedCode, config:SameLineConfig, configWhitespace:WhitespaceConfig) {
		var tokens:Array<TokenTree> = parsedCode.root.filter([BrOpen], ALL);
		for (token in tokens) {
			var type:BrOpenType = TokenTreeCheckUtils.getBrOpenType(token);
			switch (type) {
				case BLOCK:
					continue;
				case TYPEDEFDECL:
					markTypedefSameLine(token, parsedCode, config, configWhitespace);
				case OBJECTDECL:
					markObjectDeclSameLine(token, parsedCode, config, configWhitespace);
				case ANONTYPE:
					markAnonTypeSameLine(token, parsedCode, config, configWhitespace);
				case UNKNOWN:
					continue;
			}
		}
	}

	static function markAnonTypeSameLine(brOpen:TokenTree, parsedCode:ParsedCode, config:SameLineConfig, configWhitespace:WhitespaceConfig) {
		if (brOpen == null) {
			return;
		}
		if (!brOpen.is(BrOpen)) {
			return;
		}
		if (!shouldAnonTypeSameLine(brOpen, parsedCode, config)) {
			var brClose:TokenTree = brOpen.access().firstOf(BrClose).token;
			if (brClose == null) {
				return;
			}
			var next:TokenInfo = parsedCode.tokenList.getNextToken(brClose);
			switch (next.token.tok) {
				case Binop(OpGt):
					parsedCode.tokenList.whitespace(brClose, NoneAfter);
				case Binop(OpAnd):
					parsedCode.tokenList.whitespace(brClose, After);
				default:
			}
			return;
		}
		var brClose:TokenTree = brOpen.access().firstOf(BrClose).token;
		parsedCode.tokenList.whitespace(brOpen, NoneAfter);
		parsedCode.tokenList.wrapAfter(brOpen, true);
		if (brClose == null) {
			return;
		}
		parsedCode.tokenList.whitespace(brClose, NoneBefore);
		parsedCode.tokenList.wrapBefore(brClose, true);
		var next:TokenInfo = parsedCode.tokenList.getNextToken(brClose);
		if (next != null) {
			switch (next.token.tok) {
				case BrOpen:
					parsedCode.tokenList.whitespace(brClose, After);
					return;
				default:
			}
		}

		// MarkWhitespace.successiveParenthesis(brOpen, parsedCode, configWhitespace.objectOpeningBracePolicy, configWhitespace.compressSuccessiveParenthesis);
		MarkWhitespace.successiveParenthesis(brClose, true, parsedCode, configWhitespace.objectClosingBracePolicy, configWhitespace.compressSuccessiveParenthesis);
	}

	static function shouldAnonTypeSameLine(brOpen:TokenTree, parsedCode:ParsedCode, config:SameLineConfig):Bool {
		if (brOpen.children == null) {
			return true;
		}
		for (child in brOpen.children) {
			switch (child.tok) {
				case Kwd(KwdVar):
					return false;
				case Binop(OpGt):
					return false;
				default:
			}
		}
		if (brOpen.children.length > config.maxAnonTypeFields + 1) {
			return false;
		}
		return true;
	}

	static function markObjectDeclSameLine(brOpen:TokenTree, parsedCode:ParsedCode, config:SameLineConfig, configWhitespace:WhitespaceConfig) {
		if (brOpen == null) {
			return;
		}
		if (!brOpen.is(BrOpen)) {
			return;
		}
		if (!shouldbjectDeclSameLine(brOpen, parsedCode, config)) {
			return;
		}
		var brClose:TokenTree = brOpen.access().firstOf(BrClose).token;
		parsedCode.tokenList.whitespace(brOpen, NoneAfter);
		parsedCode.tokenList.wrapAfter(brOpen, true);
		if (brClose == null) {
			return;
		}
		parsedCode.tokenList.whitespace(brClose, NoneBefore);
		parsedCode.tokenList.wrapBefore(brClose, true);
		var next:TokenInfo = parsedCode.tokenList.getNextToken(brClose);
		if (next != null) {
			switch (next.token.tok) {
				case BrOpen:
					parsedCode.tokenList.whitespace(brClose, After);
					return;
				default:
			}
		}

		// MarkWhitespace.successiveParenthesis(brOpen, parsedCode, configWhitespace.objectOpeningBracePolicy, configWhitespace.compressSuccessiveParenthesis);
		MarkWhitespace.successiveParenthesis(brClose, true, parsedCode, configWhitespace.objectClosingBracePolicy, configWhitespace.compressSuccessiveParenthesis);
	}

	static function shouldbjectDeclSameLine(brOpen:TokenTree, parsedCode:ParsedCode, config:SameLineConfig):Bool {
		if (brOpen.children == null) {
			return true;
		}
		if (brOpen.children.length > config.maxObjectFields + 1) {
			return false;
		}
		return true;
	}

	static function markTypedefSameLine(brOpen:TokenTree, parsedCode:ParsedCode, config:SameLineConfig, configWhitespace:WhitespaceConfig) {}

	static function markDollarSameLine(parsedCode:ParsedCode, config:SameLineConfig, configWhitespace:WhitespaceConfig) {
		var tokens:Array<TokenTree> = parsedCode.root.filterCallback(function(token:TokenTree, index:Int):FilterResult {
			return switch (token.tok) {
				case Dollar(_):
					FOUND_SKIP_SUBTREE;
				default:
					GO_DEEPER;
			}
		});
		for (token in tokens) {
			var brOpen:TokenTree = token.access().firstChild().is(BrOpen).token;
			if (brOpen == null) {
				continue;
			}
			var brClose:TokenTree = brOpen.access().firstOf(BrClose).token;
			parsedCode.tokenList.whitespace(brOpen, None);
			parsedCode.tokenList.whitespace(brClose, None);
			parsedCode.tokenList.wrapBefore(brOpen, false);
			parsedCode.tokenList.wrapAfter(brOpen, false);
			parsedCode.tokenList.wrapBefore(brClose, false);
			parsedCode.tokenList.wrapAfter(brClose, false);
		}
	}

	static function markFunction(token:TokenTree, parsedCode:ParsedCode, configSameLine:SameLineConfig) {
		var body:TokenTree = token.access().firstChild().isCIdent().token;
		if (body == null) {
			body = token.access().firstChild().is(Kwd(KwdNew)).token;
		}
		if (body == null) {
			body = token;
		}
		if ((body == null) || (body.children == null)) {
			return;
		}
		for (child in body.children) {
			switch (child.tok) {
				case DblDot:
				#if (haxe_ver >= 4.0)
				case Kwd(KwdFinal):
				#end
				case Const(CIdent("final")):
				case Kwd(KwdPublic):
				case Kwd(KwdPrivate):
				case Kwd(KwdStatic):
				case Kwd(KwdOverride):
				case Kwd(KwdExtern):
				case Kwd(KwdInline):
				case Kwd(KwdMacro):
				case BrOpen:
					return;
				case Semicolon:
					return;
				case POpen:
				case At:
				case CommentLine(_):
					return;
				default:
					applySameLinePolicy(child, parsedCode, configSameLine.functionBody);
					return;
			}
		}
	}

	static inline function get_onMobile():Bool {
		return #if foo true #else false #end;
	}
}