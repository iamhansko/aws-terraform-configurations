import { AuthenticationDetails, CognitoUserPool, CognitoUser, CognitoUserAttribute } from 'amazon-cognito-identity-js';
import { fromCognitoIdentityPool } from '@aws-sdk/credential-providers';
import { S3Client, ListObjectsV2Command } from '@aws-sdk/client-s3';
import axios from 'axios';
import QRCode from 'qrcode';
import { POOL_DATA } from './cognito-env.js';

const userPool = new CognitoUserPool(POOL_DATA);
let cognitoUser;

const domEls = {
name: document.getElementById('floatingName') || {},
username: document.getElementById('floatingUsername') || {},
username1: document.getElementById('floatingUsername1') || {},
email: document.getElementById('floatingEmail') || {},
password: document.getElementById('floatingPassword') || {},
password1: document.getElementById('floatingPassword1') || {},
bucket: document.getElementById('floatingBucket') || {},
prefix: document.getElementById('floatingPrefix') || {}
};

const parseJwt = token => {
const base64Url = token.split('.')[1];
const base64 = base64Url.replace('-', '+').replace('_', '/');
return JSON.parse(window.atob(base64));
};

const getVal = inVal => domEls[inVal].value || '';
const dataFmt = inVal => ({ Name: inVal, Value: getVal(inVal) });
const getAttr = inVal => new CognitoUserAttribute(inVal);


/**
* Displaying important messages on screen
*/
const alert = (message, type) => {
const wrapper = document.createElement('div');
const alertPlaceholder = document.getElementById('liveAlertPlaceholder');

wrapper.innerHTML = [
    `<div class='alert alert-${type} alert-dismissible' role='alert'>`,
    `   <div>${message}</div>`,
    `   <button type='button' class='btn-close' data-bs-dismiss='alert' aria-label='Close'></button>`,
    `</div>`
].join('');

alertPlaceholder.append(wrapper);
}


/**
* Configure some listeners when the DOM is ready
*/
(() => {
'use strict'
const signInForm = document.getElementById('sign-in-form');
const signUpForm = document.getElementById('sign-up-form');
const mfaForm = document.getElementById('mfa-form');
const callApisForm = document.getElementById('call-apis-form');
const s3Form = document.getElementById('s3-form');

document.getElementById('continue-mfa').addEventListener('click', event => {
    continueMFA();
});

// A button rather than a submit: only the username is needed, so the form's other required fields must not
// block it.
document.getElementById('resend-code').addEventListener('click', event => {
    resendCode();
});

signInForm.addEventListener('submit', event => {
    signInForm.classList.add('was-validated');
    event.preventDefault();
    event.stopPropagation();
    if (signInForm.checkValidity()) (event.submitter.innerText === 'Sign In') ? signIn() : signOut();
}, false);

signUpForm.addEventListener('submit', event => {
    signUpForm.classList.add('was-validated');
    event.preventDefault();
    event.stopPropagation();
    if (signUpForm.checkValidity()) signUp();
}, false);

mfaForm.addEventListener('submit', event => {
    mfaForm.classList.add('was-validated');
    event.preventDefault();
    event.stopPropagation();
    if (mfaForm.checkValidity()) (event.submitter.innerText === 'Enable MFA') ? enableMFA() : disableMFA();
}, false);

callApisForm.addEventListener('submit', event => {
    callApisForm.classList.add('was-validated');
    event.preventDefault();
    event.stopPropagation();
    if (callApisForm.checkValidity()) callAPIGW();
}, false);

s3Form.addEventListener('submit', event => {
    s3Form.classList.add('was-validated');
    event.preventDefault();
    event.stopPropagation();
    if (s3Form.checkValidity()) listFiles();
}, false);
})()

/**
* Add Sign Up
*
* Changed from the workshop's version, which asked for the confirmation code before it looked at the result
* and only logged a failure to the console. A sign-up that failed - most often UsernameExistsException, from
* submitting again after the first code seemed not to arrive - still put up the code prompt, for a code that
* had not been sent, and nothing on the page said why. It also offered no way to have a code sent again, so a
* user left UNCONFIRMED could only sign up again and hit the same hidden error.
*/
const signUp = () => {
const attributeList = [];

attributeList.push(getAttr(dataFmt('email')));
attributeList.push(getAttr(dataFmt('name')));

userPool.signUp(getVal('username'), getVal('password'), attributeList, null, (err, result) => {
    if (err) {
    console.log(err);
    const hint = err.code === 'UsernameExistsException'
        ? ' If that sign-up was never confirmed, use Resend Code to have a new code sent.'
        : '';
    alert((err.message || JSON.stringify(err)) + hint, 'danger');
    return;
    }

    console.log('Success:', result);
    confirmSignUp(result.user, result.codeDeliveryDetails);
});
}

/**
* Resend the confirmation code to a user who signed up and was never confirmed
*/
const resendCode = () => {
if (!getVal('username')) {
    alert('Enter the username to resend the confirmation code to.', 'warning');
    return;
}

const user = new CognitoUser({ Username: getVal('username'), Pool: userPool });
user.resendConfirmationCode((err, result) => {
    if (err) {
    console.log(err);
    alert(err.message || JSON.stringify(err), 'danger');
    return;
    }

    console.log('Resent:', result);
    confirmSignUp(user, result.CodeDeliveryDetails);
});
}

/**
* Ask for the code Cognito just sent, and confirm the user with it
*
* The prompt names the masked address Cognito reports sending to (s***@g***), so a code that does not arrive
* can be told apart from one that went somewhere else. Cognito's default email gives no other trace of it.
*/
const confirmSignUp = (user, codeDeliveryDetails) => {
const destination = (codeDeliveryDetails && codeDeliveryDetails.Destination) || 'the email address you signed up with';
const confirmationCode = prompt(`Please enter the confirmation code sent to ${destination}.\nIt comes from no-reply@verificationemail.com - check the spam folder if it is not in the inbox.`);

if (!confirmationCode) {
    alert('No code entered, so the user is still unconfirmed. Use Resend Code to have a new code sent.', 'warning');
    return;
}

user.confirmRegistration(confirmationCode.trim(), true, (err, result) => {
    if (err) {
    console.log(err);
    alert(err.message || JSON.stringify(err), 'danger');
    return;
    }
    console.log('call result:', result);
    alert('Sign Up Successful!', 'success');
});
}

/**
* Add Sign In
*/
const signIn = () => {
const authenticationDetails = new AuthenticationDetails (
    { Username: getVal('username1'), Password: getVal('password1') }
);

cognitoUser = new CognitoUser({ Username: getVal('username1'), Pool: userPool });
cognitoUser.authenticateUser(authenticationDetails, {
    onSuccess: (result) => {
    const idToken = result.getIdToken().getJwtToken();
    const accessToken = result.getAccessToken().getJwtToken();

    console.log('Access Token:', parseJwt(accessToken));
    console.log('ID Token:', parseJwt(idToken));

    alert('Sign In Successful', 'success');
    },

    onFailure: (err) => {
    alert(err.message || JSON.stringify(err, null, 2), 'danger');
    },

    totpRequired: function (codeDeliveryDetails) {
    console.log('mfaRequired:', codeDeliveryDetails);
    const verificationCode = prompt('Please input second factor code:', '');
    cognitoUser.sendMFACode(verificationCode, this, 'SOFTWARE_TOKEN_MFA');
    },
});
}

/**
* Add Sign Out
*/
const signOut = () => {
cognitoUser.signOut();
document.getElementById('sign-in-form').classList.remove('was-validated');
domEls.username1.value = '';
domEls.password1.value = '';
alert('Signed Out.', 'success');
}

/**
* Enable MFA
*/
const enableMFA = () => {
cognitoUser.associateSoftwareToken({
    onSuccess: function(result) {
    console.log(result);
    },
    associateSecretCode: (secretCode) => {
    console.log('MFASecretCode: ', secretCode);

    const canvas = document.getElementById('qrcanvas');
    const tokenObj = cognitoUser.signInUserSession.idToken.payload;
    const totpUri = 'otpauth://totp/MFA:' + tokenObj['email'] + '?secret=' + secretCode + '&issuer=CognitoJSPOC';

    QRCode.toCanvas(canvas, totpUri, (error) => {
        if (error) console.error(error);
        console.log('QR Code Success!');
        document.getElementById('continue-mfa').classList.remove('d-none');
    });
    },

    onFailure: (err) => {
    console.log(err);
    alert(err.message || JSON.stringify(err, null, 2), 'danger');
    }
});
}

/**
* Continue MFA
*/
const continueMFA = () => {
const totpCode = prompt('Enter software token code:');

cognitoUser.verifySoftwareToken(totpCode, 'SoftwareToken', {
    onSuccess: function(result) {
    console.log(result);
    cognitoUser.setUserMfaPreference(
        null,
        { PreferredMfa : true, Enabled: true },
        (err, result) => {
        if (err) {
            console.error(err);
            alert(JSON.stringify(err.message, null, 2), 'success');
        } else {
            console.log('setUserMfaPreference call result:', result);
            document.getElementById('continue-mfa').classList.add('d-none');
            alert('MFA Enabled', 'success');
        }
        }
    );
    },

    onFailure: (err) => {
    console.log(err);
    alert(err.message || JSON.stringify(err, null, 2), 'danger');
    }
});
}

/**
* Disable MFA
*/
const disableMFA = () => {
const mfaSettings = {
    PreferredMfa : false,
    Enabled : false
};

cognitoUser.setUserMfaPreference(mfaSettings, mfaSettings, (err, result) => {
    if (err) {
    console.error(err);
    alert(JSON.stringify(err.message, null, 2), 'success');
    } else {
    console.log('Clear MFA call result:', result);
    alert('MFA Disabled', 'success');
    }
});
}

/**
* Call protected APIGW endpoint
*
* Important:
* - Make sure API GW Cognito Authorizer configuration is complete
* - Make sure the API accepts id-token (no OAuth scope defined in authorization)
* - You can only use id-token since custom scopes are not supported when SDK is used
*/
const callAPIGW = () => {
const headers = {
    'Content-Type': 'application/json',
    'Authorization': cognitoUser.signInUserSession.accessToken.jwtToken
};

console.log('headers:', headers);

axios.get(POOL_DATA.ServiceEndpoint, { headers: headers })
    .then((response) => {
    console.log('API GW Response:', response.data);
    alert(JSON.stringify(response.data, null, 2), 'success');
    }).catch((err) => {
    console.error('Call API GW Error:', err);
    alert(err.message || JSON.stringify(err, null, 2), 'danger');
    });
}

/**
* List files in S3 bucket
*
* - Identity Pool created and configured to use User Pool as IdP
* - Permissions defined on the IAM role to allow s3 list
* - Bucket created with proper x-origin policy to allow calls
*/
const listFiles = () => {
const client = new S3Client({
    region: POOL_DATA.Region,
    credentials: fromCognitoIdentityPool({
    clientConfig: {region: POOL_DATA.Region},
    identityPoolId: POOL_DATA.IdentityPoolId,
    logins: { [`cognito-idp.${POOL_DATA.Region}.amazonaws.com/${POOL_DATA.UserPoolId}`]: cognitoUser.signInUserSession.idToken.jwtToken }
    }),
});

const command = new ListObjectsV2Command({
    Bucket: getVal('bucket'),
    Prefix: getVal('prefix')
});
client.send(command)
    .then(response => {
    console.log('S3 List:', JSON.stringify(response.Contents, null, 2));
    if (response.Contents === undefined) alert('There was a problem', 'danger');
    else alert(JSON.stringify(response.Contents, null, 2), 'success');
    }).catch((err) => {
    console.error('S3 List Error:', err);
    alert(err.message || JSON.stringify(err, null, 2), 'danger');
    });
}
