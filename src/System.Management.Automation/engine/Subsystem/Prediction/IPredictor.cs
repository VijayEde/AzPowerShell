// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

using System;
using System.Collections.Generic;
using System.Management.Automation.Language;
using System.Threading;

namespace System.Management.Automation.Subsystem
{
    /// <summary>
    /// Interface for implementing a predictor plugin.
    /// </summary>
    public interface IPredictor : ISubsystem
    {
        /// <summary>
        /// Default implementation. No function is required for a predictor.
        /// </summary>
        Dictionary<string, string> ISubsystem.FunctionsToDefine => null;

        /// <summary>
        /// Default implementation for `ISubsystem.Kind`.
        /// </summary>
        SubsystemKind ISubsystem.Kind => SubsystemKind.CommandPredictor;

        /// <summary>
        /// Gets a value indicating whether the predictor supports early processing.
        /// </summary>
        bool SupportEarlyProcessing { get; }

        /// <summary>
        /// Gets a value indicating whether the predictor accepts feedback about the previous suggestion.
        /// </summary>
        bool AcceptFeedback { get; }

        /// <summary>
        /// A command line was accepted to execute.
        /// The predictor can start processing early as needed with the latest history.
        /// </summary>
        /// <param name="history">History command lines provided as references for prediction.</param>
        void EarlyProcessWithHistory(IReadOnlyList<string> history);

        /// <summary>
        /// The suggestion given by the predictor was accepted.
        /// </summary>
        /// <param name="acceptedSuggestion">The accepted suggestion text.</param>
        void LastSuggestionAccepted(string acceptedSuggestion);

        /// <summary>
        /// The suggestion given by the predictor was denied.
        /// </summary>
        void LastSuggestionDenied();

        /// <summary>
        /// Get the predictive suggestions.
        /// </summary>
        /// <param name="context">The <see cref="PredictionContext"/> object to be used for prediction.</param>
        /// <param name="cancellationToken">The cancellation token to cancel the prediction.</param>
        /// <returns>A list of predictive suggestions.</returns>
        List<string> GetSuggestion(PredictionContext context, CancellationToken cancellationToken);
    }

    /// <summary>
    /// Context information about the user input.
    /// </summary>
    public class PredictionContext
    {
        /// <summary>
        /// Gets the abstract syntax tree (AST) generated from parsing the user input.
        /// </summary>
        public Ast InputAst { get; }

        /// <summary>
        /// Gets the tokens generated from parsing the user input.
        /// </summary>
        public Token[] InputTokens { get; }

        /// <summary>
        /// Gets the cursor position, which is assumed always at the end of the input line.
        /// </summary>
        public IScriptPosition CursorPosition { get; }

        /// <summary>
        /// Gets the token at the cursor.
        /// </summary>
        public Token TokenAtCursor { get; }

        /// <summary>
        /// Gets all ASTs that are related to the cursor position,
        /// which is assumed always at the end of the input line.
        /// </summary>
        public IReadOnlyList<Ast> RelatedAsts { get; }

        /// <summary>
        /// Initializes a new instance of the <see cref="PredictionContext"/> from the AST and tokens that represent the user input.
        /// </summary>
        /// <param name="inputAst">The <see cref="Ast"/> object from parsing the current command line input.</param>
        /// <param name="inputTokens">The <see cref="Token"/> objects from parsing the current command line input.</param>
        public PredictionContext(Ast inputAst, Token[] inputTokens)
        {
            var cursor = inputAst.Extent.EndScriptPosition;
            var astContext = CompletionAnalysis.ExtractAstContext(inputAst, inputTokens, cursor);

            InputAst = inputAst;
            InputTokens = inputTokens;
            CursorPosition = cursor;
            TokenAtCursor = astContext.TokenAtCursor;
            RelatedAsts = astContext.RelatedAsts;
        }

        /// <summary>
        /// Creates a context instance from the user input line.
        /// </summary>
        /// <param name="input">The user input.</param>
        /// <returns>A <see cref="PredictionContext"/> object.</returns>
        public static PredictionContext Create(string input)
        {
            Ast ast = Parser.ParseInput(input, out Token[] tokens, out _);
            return new PredictionContext(ast, tokens);
        }
    }
}
