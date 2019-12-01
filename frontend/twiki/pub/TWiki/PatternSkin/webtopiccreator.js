var webtopiccreatorrules = {
	'#newtopicform' : function(el) {
		// start with a check
		canSubmit(el,false);
		el.onsubmit = function () {
			return canSubmit(this,true);
		}
	},
	'#topic' : function(el) {
		// focus input field
		el.focus();
		el.onkeyup = function() {
			//alert("onkeyup topic");
			canSubmit(this.form,false);
		}
		el.onchange = function() {
			canSubmit(this.form,false);
		}
		el.onblur = function() {
			canSubmit(this.form,true);
		}
	},
	'#nonwikiword' : function(el) {
		el.onchange = function() {
			canSubmit(this.form,false);
		}
		el.onmouseup = function() {
			canSubmit(this.form,false);
		}
	},
	'#pickparent' : function(el) {
		el.onclick = function() {
			return passFormValuesToNewLocation(getQueryUrl());
		}
	},
	'#viewtemplates' : function(el) {
		el.onclick = function() {
			openTemplateWindow();
			return false;
		}
	}
};
Behaviour.register(webtopiccreatorrules);

/**
Checks if the entered topic name is a valid WikiWord.
If so, enables the submit button, if not: enables the submit button if the user allows non-WikiWords as topic name; otherwise disables the submit button and returns 'false'.
Automatically removes spaces from entered name.
Automatically strips illegal characters.
If non-WikiWords are not allowed, capitalizes words (separated by space).
If non-WikiWords _are_ allowed, capitalizes sentence.
The generated topic name is written to a 'feedback' field.
@param inForm : pointer to the form
@param inShouldConvertInput : true: a new name is created from the entered name
@return True: submit is enabled and topic creation is allowed; false: submit is disabled and topic creation should be inhibited.
*/
function canSubmit(inForm, inShouldConvertInput) {

	var inputForTopicName = inForm.topic.value;

	/* Topic names of zero length are not allowed */
	if (inputForTopicName.length == 0) {
		disableSubmit(inForm.submit);
		/* Update feedback field */
		twiki.HTML.setHtmlOfElementWithId("webTopicCreatorFeedback", "");
		return false;
	}

	var userAllowsNonWikiWord = 
          ( ( inForm.nonwikiword != undefined ) && inForm.nonwikiword.checked ) ? true : false;

	/*
	if necessary, create a WikiWord from the input name
	(when a non-WikiWord is not allowed)
	*/
	if( userAllowsNonWikiWord ) {
		inputForTopicName = capitalizeFirstChar( inputForTopicName );
		inputForTopicName = removeSpacesAndPunctuation( inputForTopicName );
	} else {
		inputForTopicName = twiki.String.capitalize( inputForTopicName );
		inputForTopicName = twiki.String.removeSpaces( inputForTopicName );
		inputForTopicName = twiki.String.removePunctuation( inputForTopicName );
	}
	
	if (inShouldConvertInput) {
		inForm.topic.value = inputForTopicName;
	}

	/* Update feedback field */
	feedbackHeader = "<strong>" + TEXT_FEEDBACK_HEADER + "</strong>";
	feedbackText = feedbackHeader + inputForTopicName;
	twiki.HTML.setHtmlOfElementWithId( "webTopicCreatorFeedback", feedbackText );

	if( twiki.String.isWikiWord( inputForTopicName ) || userAllowsNonWikiWord ) {
		enableSubmit(inForm.submit);
		return true;
	} else {
		disableSubmit(inForm.submit);
		return false;
	}
}
function removeSpacesAndPunctuation (inText) {
        inText = twiki.String.removeSpaces(inText);
        var allowedRegex = "[^" + ALLOWED_URL_CHARS + "]";
        var re = new RegExp(allowedRegex, "g");
        return inText.replace(re, "");
}
function capitalizeFirstChar (inText) {
	return inText.substr(0,1).toUpperCase() + inText.substr(1);
}
/**
@param inState: true or false
*/
function enableSubmit(inButton) {
	if (!inButton) return;
	twiki.CSS.removeClass(inButton, "twikiSubmitDisabled");
	inButton.disabled = false;
}
function disableSubmit(inButton) {
	if (!inButton) return;
	twiki.CSS.addClass(inButton, "twikiSubmitDisabled");
	inButton.disabled = true;
}
function passFormValuesToNewLocation (inUrl) {
	var url = inUrl;
	// remove current parameters so we can override these with newly entered values
	url = url.split("?")[0];
	// read values from form
	var params = "";
	var newtopic = document.forms.newtopicform.topic.value;
	params += ";newtopic=" + newtopic;
	var topicparent = document.forms.newtopicform.topicparent.value;
	params += ";topicparent=" + topicparent;
	var templatetopic = document.forms.newtopicform.templatetopic.value;
	params += ";templatetopic=" + templatetopic;
	var pickparent = URL_PICK_PARENT;
	params += ";pickparent=" + pickparent;
	params += ";template=" + URL_TEMPLATE;
	url += "?" + params;
	document.location.href = url;
	return false;
}
