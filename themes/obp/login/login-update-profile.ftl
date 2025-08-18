<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=messagesPerField.exists('global') displayRequiredFields=true; section>
    <#if section = "header">
        ${msg("loginProfileTitle")}
    <#elseif section = "form">
        <form id="kc-update-profile-form" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">

            <#-- Use user profile if available, otherwise fallback to basic fields -->
            <#if profile?? && profile.attributes??>
                <#-- Modern user profile approach -->
                <#assign currentGroup="">
                <#list profile.attributes as attribute>
                    <#if attribute.name != 'locale' || !realm.internationalizationEnabled || !locale.currentLanguageTag?has_content>
                        <div class="${properties.kcFormGroupClass!}">
                            <div class="${properties.kcLabelWrapperClass!}">
                                <label for="${attribute.name}" class="${properties.kcLabelClass!}">
                                    <#if attribute.displayName??>
                                        ${attribute.displayName}
                                    <#else>
                                        ${msg(attribute.name)}
                                    </#if>
                                    <#if attribute.required>*</#if>
                                </label>
                            </div>
                            <div class="${properties.kcInputWrapperClass!}">
                                <input type="text" id="${attribute.name}" name="${attribute.name}"
                                       value="${(attribute.value!'')}"
                                       class="${properties.kcInputClass!}"
                                       aria-invalid="<#if messagesPerField.existsError('${attribute.name}')>true</#if>"
                                       <#if attribute.required>required</#if> />

                                <#if messagesPerField.existsError('${attribute.name}')>
                                    <span id="input-error-${attribute.name}" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                        ${kcSanitize(messagesPerField.get('${attribute.name}'))?no_esc}
                                    </span>
                                </#if>
                            </div>
                        </div>
                    <#else>
                        <input type="hidden" id="${attribute.name}" name="${attribute.name}" value="${locale.currentLanguageTag}"/>
                    </#if>
                </#list>
            <#else>
                <#-- Fallback for legacy user management -->
                <div class="${properties.kcFormGroupClass!}">
                    <div class="${properties.kcLabelWrapperClass!}">
                        <label for="firstName" class="${properties.kcLabelClass!}">${msg("firstName")}</label>
                    </div>
                    <div class="${properties.kcInputWrapperClass!}">
                        <input type="text" id="firstName" name="firstName" value="${(user.firstName!'')}"
                               class="${properties.kcInputClass!}"
                               aria-invalid="<#if messagesPerField.existsError('firstName')>true</#if>" />

                        <#if messagesPerField.existsError('firstName')>
                            <span id="input-error-firstName" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                ${kcSanitize(messagesPerField.get('firstName'))?no_esc}
                            </span>
                        </#if>
                    </div>
                </div>

                <div class="${properties.kcFormGroupClass!}">
                    <div class="${properties.kcLabelWrapperClass!}">
                        <label for="lastName" class="${properties.kcLabelClass!}">${msg("lastName")}</label>
                    </div>
                    <div class="${properties.kcInputWrapperClass!}">
                        <input type="text" id="lastName" name="lastName" value="${(user.lastName!'')}"
                               class="${properties.kcInputClass!}"
                               aria-invalid="<#if messagesPerField.existsError('lastName')>true</#if>" />

                        <#if messagesPerField.existsError('lastName')>
                            <span id="input-error-lastName" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                ${kcSanitize(messagesPerField.get('lastName'))?no_esc}
                            </span>
                        </#if>
                    </div>
                </div>

                <div class="${properties.kcFormGroupClass!}">
                    <div class="${properties.kcLabelWrapperClass!}">
                        <label for="email" class="${properties.kcLabelClass!}">${msg("email")}</label>
                    </div>
                    <div class="${properties.kcInputWrapperClass!}">
                        <input type="text" id="email" name="email" value="${(user.email!'')}"
                               class="${properties.kcInputClass!}"
                               aria-invalid="<#if messagesPerField.existsError('email')>true</#if>" />

                        <#if messagesPerField.existsError('email')>
                            <span id="input-error-email" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                ${kcSanitize(messagesPerField.get('email'))?no_esc}
                            </span>
                        </#if>
                    </div>
                </div>

                <#if realm.editUsernameAllowed>
                    <div class="${properties.kcFormGroupClass!}">
                        <div class="${properties.kcLabelWrapperClass!}">
                            <label for="username" class="${properties.kcLabelClass!}">${msg("username")}</label>
                        </div>
                        <div class="${properties.kcInputWrapperClass!}">
                            <input type="text" id="username" name="username" value="${(user.username!'')}"
                                   class="${properties.kcInputClass!}"
                                   aria-invalid="<#if messagesPerField.existsError('username')>true</#if>" />

                            <#if messagesPerField.existsError('username')>
                                <span id="input-error-username" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                    ${kcSanitize(messagesPerField.get('username'))?no_esc}
                                </span>
                            </#if>
                        </div>
                    </div>
                </#if>
            </#if>

            <div class="${properties.kcFormGroupClass!}">
                <div id="kc-form-options" class="${properties.kcFormOptionsClass!}">
                    <div class="${properties.kcFormOptionsWrapperClass!}">
                    </div>
                </div>

                <div id="kc-form-buttons" class="${properties.kcFormButtonsClass!}">
                    <#if isAppInitiatedAction??>
                        <input class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonLargeClass!}" type="submit" value="${msg("doSubmit")}" />
                        <button class="${properties.kcButtonClass!} ${properties.kcButtonDefaultClass!} ${properties.kcButtonLargeClass!}" type="submit" name="cancel-aia" value="true" formnovalidate>${msg("doCancel")}</button>
                    <#else>
                        <input class="${properties.kcButtonClass!} ${properties.kcButtonPrimaryClass!} ${properties.kcButtonBlockClass!} ${properties.kcButtonLargeClass!}" type="submit" value="${msg("doSubmit")}" />
                    </#if>
                </div>
            </div>
        </form>
    </#if>
</@layout.registrationLayout>
