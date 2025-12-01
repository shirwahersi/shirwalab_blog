+++
title = 'Configure AWS IAM Identity Center (successor to AWS SSO) for SSO with Microsoft Entra ID'
date = 2025-12-01T11:57:28Z
draft = false
+++


In this post, you will learn how to integrate AWS IAM Identity Center (successor to AWS Single Sign-On) with Microsoft Entra ID. When you integrate AWS IAM Identity Center with Microsoft Entra ID, you can:

* Control in Microsoft Entra ID who has access to AWS IAM Identity Center.
* Enable your users to be automatically signed-in to AWS IAM Identity Center with their Microsoft Entra accounts.
* Manage your accounts in one central location.

## Part 1: Initial AWS Identity Center Setup

The first step is to prepare AWS to receive identity information from an external source. We will use AWS Identity Center (the successor to AWS Single Sign-On) for this.

1.1 Get AWS SAML Metadata

This file contains the configuration details that Microsoft Entra ID needs to communicate with AWS.

1. In the AWS Identity Center console, navigate to the Settings page in the left-hand navigation pane.

2. On the Settings page, look for the Identity source section, then click the Actions dropdown menu and select Change identity source.

![aws-sso ](/static/images/aws-sso-setup/1.png)

3. On the “Choose identity source” page, select the radio button for `External identity provider` and then click the Next button.

4. On the “Configure external identity provider” page, under the “Service provider metadata” section, you will see a button to Download metadata file. Click it to download the `AWS-metadata.xml` file.

![aws-sso metadata.xml ](/static/images/aws-sso-setup/2.png)

> **Note:** Stay on this page as we will come back to it to upload SAML Metadata from Microsoft Entra ID.

## Part 2: Microsoft Entra ID Application Configuration

Now we will configure the Microsoft Entra ID application to integrate with AWS. 

2.1 Sign in to the [Microsoft Entra admin portal](https://entra.microsoft.com/).

2.2 From the left-hand navigation pane, select Enterprise Applications.

![azure app ](/static/images/aws-sso-setup/3.png)

2.3 Click New Application to create a new integration, then click `Create your own application`.

![azure app ](/static/images/aws-sso-setup/4.png)

2.4 Provide a name for the application (for example, AWS SSO) and select Create.

![azure app ](/static/images/aws-sso-setup/5.png)


2.5 Click on `Single sign-on`, then select SAML.

![azure app ](/static/images/aws-sso-setup/6.png)

2.6 A pop-up window will appear. Click the Upload metadata file button.

2.7 Click the folder icon to browse your computer and upload the AWS-metadata.xml file that you downloaded from AWS in Part 1.

![azure app ](/static/images/aws-sso-setup/7.png)


Once uploaded, the Identifier (Entity ID) and Reply URL (Assertion Consumer Service URL) fields will be automatically populated. Click Save and then close the pop-up window.

2.8 Get Entra ID SAML Metadata

> This file contains Entra ID’s configuration details that AWS needs to trust it.

2.8.1 On the “Set up Single Sign-On with SAML” page, scroll down to the SAML Signing Certificate section. Next to Federation Metadata XML, click the Download button. This will download a file named `AWS SSO.xml` (or similar).

![azure app ](/static/images/aws-sso-setup/8.png)


2.9 Upload Entra ID SAML Metadata 

2.9.1 Go back to the AWS Identity Center console.

2.9.2 Navigate to Settings and then to the Identity source section.

2.9.3 Under “Identity provider metadata,” click Choose file and upload the Federation Metadata XML file you downloaded from Entra ID in step 2.8.1.

![azure app ](/static/images/aws-sso-setup/9.png)

2.9.4 Click Next: Review, then type ACCEPT into the text box to confirm the change.

2.9.5 Click the Change identity source button to save the changes.

## Part 3: Configure Provisioning (SCIM)

SCIM (System for Cross-domain Identity Management) is an open-standard protocol that enables an organisation to automatically create, update, and delete user accounts across many cloud applications from one central directory—no manual administrative work required. Think of it as the “identity sync engine” behind the scenes. 

3.1 On the “Provisioning” page, click the Get started button.

3.2 Change the Provisioning Mode dropdown from “Manual” to Automatic.

![azure app ](/static/images/aws-sso-setup/10.png)

3.3 In another tab, go to the AWS Identity Center console → Settings page.

3.4 Under the Automatic provisioning section, click the Enable button.

![azure app ](/static/images/aws-sso-setup/11.png)

3.5 A new section will appear with a SCIM endpoint URL and an Access token.


![azure app ](/static/images/aws-sso-setup/12.png)

3.6 Copy both the SCIM endpoint and the Access token. We will need these values in Microsoft Entra ID. Be careful not to include any extra spaces when copying.


3.7 Go back to the Entra admin centre, then in the “Admin Credentials” section, paste the SCIM endpoint and Access token you copied from AWS in step 3.5 into the Tenant URL and Secret Token fields, respectively.

![azure app ](/static/images/aws-sso-setup/13.png)


3.8 Click `Test Connection` to test the connection to the AWS SCIM endpoint.

## Part 4: Assign Users and Groups

Create groups and assign users to these groups. Microsoft Entra ID SCIM will sync these groups and users to AWS every 40 minutes, or you can optionally force a manual sync.


4.1 Go to the Entra admin centre → Groups → All groups → New group.

![azure app ](/static/images/aws-sso-setup/14.png)

4.2 Under Members, select users, then click Select and Create.

4.3 From the left-hand navigation pane, select Enterprise Applications → AWS SSO.

4.4 In the application’s menu, click on Assign users and groups.

4.5 On the “Users and groups” page, click the Add user/group button.

4.6 A new panel will appear. Click the link under the “Users and groups” heading to select users.

4.7 A pop-up window will open. In the search box, find and select the security groups or individual users who need access to AWS.

4.8 Click the Select button at the bottom of the pop-up window.

4.9 Back on the “Add Assignment” panel, click the Assign button.

4.10 A notification will appear confirming that the users/groups have been successfully assigned.

![azure app ](/static/images/aws-sso-setup/15.png)

4.11 Sync groups and users to AWS

You can either wait 40 minutes for automatic sync or manually trigger a sync via the Provisioning tab.

![azure app ](/static/images/aws-sso-setup/16.png)

Once SCIM sync is successful, you can verify whether Entra ID groups and users are available in AWS via IAM Identity Center.

![azure app ](/static/images/aws-sso-setup/17.png)


## Part 5: Create Permission Sets

A permission set defines a user’s access level in an AWS account.

5.1 In the AWS Identity Center console, navigate to Permission sets in the left navigation pane.

5.2 Click the Create permission set button.

5.3 On the “Select permission set type” page, you can choose a Predefined permission set (e.g., DatabaseAccess) or create a Custom permission set. For this guide, select AdministratorAccess and click Next.

5.4 On the next screen, review the policies, then click Next.

5.5 Review the details, rename if desired, then click Create.

![azure app ](/static/images/aws-sso-setup/18.png)

5.6 Repeat the same process for all permission sets needed.


## Part 6: Assign Users and Groups

This is the final step to grant access.

6.1 In the AWS Identity Center console, go to AWS accounts in the left navigation pane and select the account you want to configure by checking the box next to it. Click the Assign users or groups button at the top.

![azure app ](/static/images/aws-sso-setup/19.png)


6.2 On the “Assign users or groups” page, select the Groups tab. You should see the groups synchronised from Entra ID via SCIM. Find and select the security group you want to grant access to (e.g., “AWS_Admins”), then click Next.

![azure app ](/static/images/aws-sso-setup/20.png)


6.3 On the “Select permission sets” page, find and select the permission set you created earlier (e.g., AWSAdministratorAccess), then click Next.

![azure app ](/static/images/aws-sso-setup/21.png)


6.4 Review the assignment details, then click Submit.




