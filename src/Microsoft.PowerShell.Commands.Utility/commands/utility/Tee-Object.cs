// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using System.Management.Automation;

using Microsoft.PowerShell.Commands.Internal.Format;

namespace Microsoft.PowerShell.Commands
{
    /// <summary>
    /// Class for Tee-object implementation.
    /// </summary>
    [Cmdlet("Tee", "Object", DefaultParameterSetName = "File", HelpUri = "https://go.microsoft.com/fwlink/?LinkID=2097034")]
    public sealed class TeeObjectCommand : PSCmdlet, IDisposable
    {
        /// <summary>
        /// Object to process.
        /// </summary>
        [Parameter(ValueFromPipeline = true)]
        public PSObject InputObject
        {
            get { return _inputObject; }

            set { _inputObject = value; }
        }

        private PSObject _inputObject;

        /// <summary>
        /// FilePath parameter.
        /// </summary>
        [Parameter(Mandatory = true, Position = 0, ParameterSetName = "File")]
        [Alias("Path")]
        public string FilePath
        {
            get { return _fileName; }

            set { _fileName = value; }
        }

        private string _fileName;

        /// <summary>
        /// Literal FilePath parameter.
        /// </summary>
        [Parameter(Mandatory = true, ParameterSetName = "LiteralFile")]
        [Alias("PSPath", "LP")]
        public string LiteralPath
        {
            get
            {
                return _fileName;
            }

            set
            {
                _fileName = value;
            }
        }

        /// <summary>
        /// Append switch.
        /// </summary>
        [Parameter(ParameterSetName = "File")]
        public SwitchParameter Append
        {
            get { return _append; }

            set { _append = value; }
        }

        private bool _append;

        /// <summary>
        /// Variable parameter.
        /// </summary>
        [Parameter(Mandatory = true, ParameterSetName = "Variable")]
        public string Variable
        {
            get { return _variable; }

            set { _variable = value; }
        }

        private string _variable;

        /// <summary>
        /// Gets or sets the stream parameter.
        /// </summary>
        [Parameter(Mandatory = true, ParameterSetName = "Stream")]
        [ValidateSet(
            "Verbose",
            "Warning",
            "Information",
            "Debug",
            "Error")]

        public string Stream
        {
            get
            {
                return _stream;
            }

            set
            {
                // Store the  upper-case value to simplify case statement
                _stream = value.ToUpper();
            }
        }

        private string _stream;

        /// <summary>
        /// </summary>
        protected override void BeginProcessing()
        {
            _commandWrapper = new CommandWrapper();
            if (string.Equals(ParameterSetName, "File", StringComparison.OrdinalIgnoreCase))
            {
                _commandWrapper.Initialize(Context, "out-file", typeof(OutFileCommand));
                _commandWrapper.AddNamedParameter("filepath", _fileName);
                _commandWrapper.AddNamedParameter("append", _append);
            }
            else if (string.Equals(ParameterSetName, "LiteralFile", StringComparison.OrdinalIgnoreCase))
            {
                _commandWrapper.Initialize(Context, "out-file", typeof(OutFileCommand));
                _commandWrapper.AddNamedParameter("LiteralPath", _fileName);
                _commandWrapper.AddNamedParameter("append", _append);
            }
            else if (string.Equals(ParameterSetName, "Stream", StringComparison.OrdinalIgnoreCase))
            {
                // no initialization needed for this parameterset
            } 
            else 
            {
                // variable parameter set
                _commandWrapper.Initialize(Context, "set-variable", typeof(SetVariableCommand));
                _commandWrapper.AddNamedParameter("name", _variable);
                // Can't use set-var's passthru because it writes the var object to the pipeline, we want just
                // the values to be written
            }
        }

        /// <summary>
        /// </summary>
        protected override void ProcessRecord()
        {
            if (string.Equals(ParameterSetName, "Stream", StringComparison.OrdinalIgnoreCase))
            { 
                string _message = _inputObject.ToString();
                switch (_stream) 
                {
                    case "VERBOSE": WriteVerbose(_message);
                                    break;
                    case "WARNING": WriteWarning(_message);
                                    break;
                    case "INFORMATION": WriteInformation(new System.Management.Automation.InformationRecord(_message, "Tee-Object"));
                                        break;
                    case "DEBUG": WriteDebug(_message);
                                break;
                    case "ERROR": Exception exc = new WriteErrorException();
                                  WriteError(new ErrorRecord(exc, _message, ErrorCategory.WriteError, _inputObject));
                                  break;
                }

            } 
            else 
            {
                _commandWrapper.Process(_inputObject);
            }
            WriteObject(_inputObject);
        }

        /// <summary>
        /// </summary>
        protected override void EndProcessing()
        {
            _commandWrapper.ShutDown();
        }

        private void Dispose(bool isDisposing)
        {
            if (!_alreadyDisposed)
            {
                _alreadyDisposed = true;
                if (isDisposing && _commandWrapper != null)
                {
                    _commandWrapper.Dispose();
                    _commandWrapper = null;
                }
            }
        }

        /// <summary>
        /// Dispose method in IDisposable.
        /// </summary>
        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        #region private
        private CommandWrapper _commandWrapper;
        private bool _alreadyDisposed;
        #endregion private
    }
}
