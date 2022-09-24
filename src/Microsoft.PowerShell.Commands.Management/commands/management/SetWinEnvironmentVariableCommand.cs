// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#if !UNIX

using System;
using System.Security;
using System.IO;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Internal;
using System.Text.RegularExpressions;

namespace Microsoft.PowerShell.Commands
{
    /// <summary>
    /// Defines the implementation of the 'Set-WinEnvironmentVariable' cmdlet.
    /// This cmdlet gets the content from EnvironmentVariable.
    /// </summary>
    [Cmdlet(VerbsCommon.Set, "WinEnvironmentVariable", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
    public class SetWinEnvironmentVariableCommand : PSCmdlet
    {

        /// <summary>
        /// Property that sets EnvironmentVariable value.
        /// </summary>
        [Parameter(Position = 0, Mandatory = true, ValueFromPipeline = true, ValueFromPipelineByPropertyName = true)]
        [AllowEmptyString]
        public string[] Value { get; set; }

        /// <summary>
        /// Specifies the Name EnvironmentVariable.
        /// </summary>
        [Parameter(Position = 1, Mandatory = true)]
        [ValidateNotNullOrEmpty]
        public string Name { get; set; }

        /// <summary>
        /// Gets or sets the EnvironmentVariableTarget.
        /// </summary>
        [Parameter(Mandatory = false)]
        [ValidateNotNullOrEmpty]
        public EnvironmentVariableTarget Target { get; set; } = EnvironmentVariableTarget.Process;

        /// <summary>
        /// Gets or sets property that sets delimiter.
        /// </summary>
        [Parameter(Mandatory = false)]
        [ValidateNotNullOrEmpty]
        public Char? Delimiter { get; set; } = null;

        /// <summary>
        /// Property that sets append parameter. This will allow to append EnvironmentVariable without remove it.
        /// </summary>
        [Parameter]
        public SwitchParameter Append { get; set; }

        /// <summary>
        /// Property that sets force parameter. This will allow to remove or set the EnvironmentVariable.
        /// </summary>
        [Parameter]
        public SwitchParameter Force{ get; set; } = false;

        private readonly List<string> _contentList = new();

        private static readonly List<String> DetectedDelimiterEnvrionmentVariable = new List<String>{"Path", "PATHEXT", "PSModulePath"};

        /// <summary>
        /// This method implements the BeginProcessing method for Set-WinEnvironmentVariable command.
        /// </summary>
        protected override void BeginProcessing()
        {
            _contentList.Clear();
            if (Target == EnvironmentVariableTarget.Process)
            {
                this.CommandInfo.CommandMetadata.ConfirmImpact = ConfirmImpact.Medium;
            }
            if (DetectedDelimiterEnvrionmentVariable.Contains(Name)) {
                Delimiter = Path.PathSeparator;
            }
            if (Append)
            {
                var content = Environment.GetEnvironmentVariable(Name, Target);

                if (!String.IsNullOrEmpty(content))
                {
                    _contentList.Insert(0, content);
                }
            }

        }

        /// <summary>
        /// This method implements the ProcessRecord method for Set-WinEnvironmentVariable command.
        /// </summary>
        protected override void ProcessRecord()
        {
            if (Value != null)
            {
                _contentList.AddRange(Value);
            }
        }

        /// <summary>
        /// This method removes all leading and trailing occurrences of a set of blank character
        /// </summary>
        /// <param name="EnvironmentVariable">EnvironmentVariable has been trimmed.</param>
        /// <param name="separatorSymbol">EnvironmentVariable separator.</param>
        public String TrimEnvironmentVariable(String EnvironmentVariable, Char separatorSymbol)
        {

            Regex duplicateSymbol = new Regex(Delimiter + "{2,}");
            Regex headSymbol = new Regex("^" + Delimiter);
            Regex trailingSymbol = new Regex(Delimiter + "$");
            Regex trimSymbolSpace = new Regex(@"[\n\r\s\t]*" + Delimiter + @"[\n\r\s\t]*");

            return trailingSymbol.Replace(
                headSymbol.Replace(
                    trimSymbolSpace.Replace(
                        duplicateSymbol.Replace(
                            EnvironmentVariable,
                            separatorSymbol.ToString()
                        ),
                        separatorSymbol.ToString()
                    ),
                    String.Empty
                ),
                String.Empty
            ).Trim();
        }

        /// <summary>
        /// This method implements the EndProcessing method for Set-WinEnvironmentVariable command.
        /// Set the EnvironmentVariable content.
        /// </summary>
        protected override void EndProcessing()
        {

            string setWinEnvironmentVariableShouldProcessTarget;

            if (_contentList.Count == 1 && String.IsNullOrEmpty(_contentList[0]) && !Append)
            {
                setWinEnvironmentVariableShouldProcessTarget = string.Format(CultureInfo.InvariantCulture, WinEnvironmentVariableResources.WinEnvironmentVariableRemoved, Name);
                if (Force || ShouldProcess(setWinEnvironmentVariableShouldProcessTarget, "Set-WinEnvironmentVariable"))
                {
                    Environment.SetEnvironmentVariable(Name, null, Target);
                }
                return;
            }

            if (String.IsNullOrEmpty(Delimiter.ToString()) && (Append || _contentList.Count > 1)) 
            {
                var message = StringUtil.Format(
                    WinEnvironmentVariableResources.DelimterNotDetected);

                ArgumentException argumentException = new ArgumentException(message);
                ErrorRecord errorRecord = new ErrorRecord(
                    argumentException,
                    "DelimiterNotDetected",
                    ErrorCategory.ParserError,
                    Name);
                ThrowTerminatingError(errorRecord);
                return;
            }

            string result = string.Join(Delimiter.ToString() ?? String.Empty, _contentList);

            if (String.IsNullOrEmpty(Delimiter.ToString()))
            {
                setWinEnvironmentVariableShouldProcessTarget = string.Format(CultureInfo.InvariantCulture, WinEnvironmentVariableResources.SetWinEnvironmentVariable, result, Name);
            }
            else 
            {
                result = TrimEnvironmentVariable(result, Delimiter.Value);

                Regex symbol2newLine = new Regex(Delimiter.ToString());
                String verboseString = symbol2newLine.Replace(result, Environment.NewLine) + Environment.NewLine;
                setWinEnvironmentVariableShouldProcessTarget = string.Format(CultureInfo.InvariantCulture, WinEnvironmentVariableResources.SetMultipleEnvironmentVariable, Name, Delimiter, verboseString);
            }

            if (Force || ShouldProcess(setWinEnvironmentVariableShouldProcessTarget, "Set-WinEnvironmentVariable"))
            {
                try
                {
                    Environment.SetEnvironmentVariable(Name, result, Target);
                }
                catch (SecurityException ex)
                {
                    var message = StringUtil.Format(
                        WinEnvironmentVariableResources.CantSetWinEnvironmentVariable,
                        Name,
                        Target);

                    SecurityException argumentException = new SecurityException(message, ex.InnerException);
                    ErrorRecord errorRecord = new ErrorRecord(
                        argumentException,
                        "PermissionDenied",
                        ErrorCategory.PermissionDenied,
                        Name);
                    ThrowTerminatingError(errorRecord);
                }
                catch (ArgumentException ex)
                {
                    var message = StringUtil.Format(
                        WinEnvironmentVariableResources.SetWinEnvironmentVariableArgumentError,
                        Name);

                    ArgumentException argumentException = new ArgumentException(message, ex.InnerException);
                    ErrorRecord errorRecord = new ErrorRecord(
                        argumentException,
                        "ArgumentError",
                        ErrorCategory.ParserError,
                        Name);
                    ThrowTerminatingError(errorRecord);
                }
            }
        }
    }
}

#endif
