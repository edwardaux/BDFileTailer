// BDFileTailer.m
//
// Copyright (c) 2013 Craig Edwards
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import <Foundation/Foundation.h>

typedef enum {
	BDFileTailerLineEndOnlyCR = 0,      // A carriage return signifies EOL
	BDFileTailerLineEndOnlyLF,          // A line feed signifies EOL
	BDFileTailerLineEndCRLF,            // Needs both CR and LF for EOL
	BDFileTailerLineEndAuto             // Automatically tries to determine which
} BDFileTailerLineEnd;

/**
 * Reads data from a passed file, and returns the contents line-by-line using either the readLine
 * or readLineAsData methods.
 *
 * Supports tailing a file (similar to `tail -f`) and also following rolled over files.
 */
@interface BDFileTailer : NSObject

/** Size of internal buffer. Can be used to affect number of physical file reads. Defaults to 4096. */
@property (nonatomic, assign) NSUInteger bufferSize;

/** Indicates how line-end will be determined. Defaults to BDFileTailerLineEndAuto */
@property (nonatomic, assign) BDFileTailerLineEnd lineEndIndicator;

/** Indicates whether the line-end characters will be stripped from the returned lines. Defaults to NO. */
@property (nonatomic, assign) BOOL shouldStripLineEnds;

/**
 * An array of NSStringEncoding enums that will be used to try and encode the data into a string. 
 * Defaults to containing NSUTF8StringEncoding.
 *
 * When a new line is read, readLine attempts to convert the raw bytes into an NSString by iterating
 * through the encodings in this list. It returns the first non-nil string that is returned from
 * [NSString initWithData:encoding:]. If you know the exact encoding, it is much more efficient to
 * set this property to only contain that encoding.  If you aren't sure, you can use multiple
 * encodings, but the process will be slower because each encoding is tried one-by-one.
 */
@property (nonatomic, strong) NSArray *encodings;

/**
 * Should we tail the file for further input?  Note that this will cause readLine to block at EOF 
 * until stopTailing is called. Defaults to NO.
 */
@property (nonatomic, assign) BOOL shouldTail;

/** If we are tailing, how frequently do we check for updates to the file. Defaults to 1 second. */
@property (nonatomic, assign) NSTimeInterval tailFrequency;

/**
 * Should we follow file renames.  This handles the case where we start reading from, say,
 * access.log, but somewhere along the way the process writing to that file closes it, renames
 * it to something else (eg. access-2013-12-25.log) and starts writing logs to a new file
 * called access.log.
 *
 * This property is only honoured if shouldTail=YES.
 */
@property (nonatomic, assign) BOOL shouldFollowRename;

/** The starting size of the file */
@property (nonatomic, readonly) NSUInteger originalFileLength;

/** The line number that was just read (1-based index) */
@property (nonatomic, readonly) NSUInteger lastLineNumber;

/** The offset within the file of the line that was just read (0-based index) */
@property (nonatomic, readonly) NSUInteger lastLineFileOffset;

/**
 * Initialise the file tailer with a url.  Returns nil if the file is unable to be opened.
 */
-(id)initWithURL:(NSURL *)url;

/**
 * Returns a single line from the input file.  If [BDTailer shouldTail] is YES, this method
 * will block until either new data is available, or [BDFileTailer stopTailing] is
 * called on another thread.
 * @return An NSData containing the raw bytes for the line.  nil if we are at EOF.
 */
-(NSData *)readLineAsData;

/**
 * Returns a single line from the input file.  If [BDTailer shouldTail] is YES, this method
 * will block until either new data is available, or [BDFileTailer stopTailing] is
 * called on another thread.
 * @return An NSString containing the raw bytes for the line.  nil if we are at EOF.
 */
-(NSString *)readLine;

/**
 * Provides a mechanism where tailing can be stopped.  Would normally have to be invoked
 * from another thread because readLine will be blocking.
 */
-(void)stopTailing;

@end
