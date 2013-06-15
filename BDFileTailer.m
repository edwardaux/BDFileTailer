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

#import "BDFileTailer.h"
#import <sys/types.h>
#import <sys/stat.h>

#define CR '\n'
#define LF '\r'

/**
 * Defines a bunch of internal properties
 */
@interface BDFileTailer ()

/** Contains a reference to the original URL */
@property (nonatomic, strong) NSURL *fileURL;
/** Points to the file we're reading from */
@property (nonatomic, strong) NSFileHandle *fileHandle;
/** Contains the original length of the file */
@property (nonatomic, assign) NSUInteger fileLength;

/** Contains the current buffer of data we've pre-read from the file */
@property (nonatomic, strong) NSData *buffer;
/** Points to the internal byte buffer of self.buffer.  Gives us a huge performance boost. */
@property (nonatomic, assign) uint8_t *bufferPointer;
/** Pre-saved length of self.buffer.  Another big performance boost. */
@property (nonatomic, assign) NSUInteger bufferLength;

/** The offset of the next byte to be checked in the buffer */
@property (nonatomic, assign) NSUInteger nextBufferOffset;

/** Keeps track of whether it is time to stop tailing yet */
@property (nonatomic, assign) BOOL shouldStopTailing;

/** The length of the last line.  Used so the lastLineFileOffset is accurate after returning the line */
@property (nonatomic, assign) NSUInteger lastLineLength;

@end


@implementation BDFileTailer

-(id)initWithURL:(NSURL *)url {
	self = [super init];
	if (self != nil) {
		
		if ([self openURL:url] == NO) {
			// uh-oh... can't open the file.
			return nil;
		}
		
		// set up some sensible defaults
		self.bufferSize = 4096;
		self.shouldTail = NO;
		self.shouldStopTailing = NO;
		self.tailFrequency = 1;
		self.encodings = @[ @(NSUTF8StringEncoding) ];
		self.lineEndIndicator = BDFileTailerLineEndAuto;
	}
	return self;
}

-(BOOL)openURL:(NSURL *)url {
	if (self.fileHandle != nil)
		[self.fileHandle closeFile];
	
	self.fileURL = url;
	self.fileHandle = [NSFileHandle fileHandleForReadingAtPath:[self.fileURL path]];
	if (self.fileHandle == nil) {
		return NO;
	}
	
	// figure out the length of the file, and then seek back to start of file
	self.fileLength = [self.fileHandle seekToEndOfFile];
	[self.fileHandle seekToFileOffset:0ULL];
	
	_lastLineFileOffset = 0;
	_lastLineNumber = 0;
	_lastLineLength = 0;
	
	return YES;
}

-(void)stopTailing {
	self.shouldStopTailing = YES;
}

/**
 * Fetches data into the internal buffer.  self.buffer will be an empty NSData if at EOF.
 * @return Whether some new data was read successfully
 */
-(BOOL)fillBuffer {
	self.buffer = [self.fileHandle readDataOfLength:self.bufferSize];
	self.nextBufferOffset = 0;
	
	// save a pointer to the internal buffer's bytes and length to improve performance
	self.bufferPointer = (uint8_t *)[self.buffer bytes];
	self.bufferLength = [self.buffer length];
	
	return self.bufferLength != 0;
}

/**
 * Gets the next byte from the internal buffer.  If we've already consumed all of the
 * buffer, then we'll go get some more buffer data from the underlying file.
 */
-(BOOL)nextByte:(uint8_t *)byte consume:(BOOL)consume {
	// firstly let's check to see if we need more buffer. If we can't
	// get any more, then we indicate there is no more data available
	if (self.nextBufferOffset >= self.bufferLength) {
		[self fillBuffer];
		if (self.bufferLength == 0)
			return NO;
	}
	
	// go get the byte we need
	*byte = self.bufferPointer[self.nextBufferOffset];
	
	// if we are consuming this, we need to shuffle the buffer pointer along, and also
	// keep track of how long this line is.
	if (consume) {
		self.nextBufferOffset++;
		_lastLineLength++;
	}
	
	return YES;
}

/**
 * Reads (and consumes) the next byte from the buffer into the passed variable.
 * @return whether a byte was available
 */
-(BOOL)readByte:(uint8_t *)byte {
	return [self nextByte:byte consume:YES];
}

/**
 * Peeks at (does not consume) the next byte from the buffer into the passed variable.
 * @return whether a byte was available
 */
-(BOOL)peekByte:(uint8_t *)byte {
	return [self nextByte:byte consume:NO];
}

/**
 * This is the guts of it!
 */
-(NSData *)readLineAsData {
	uint8_t byte;
	NSMutableData *data = [NSMutableData dataWithCapacity:100];
	
	// we've hung on to the last line's file offset long enough. If they haven't got
	// it by now, it is too late.
	_lastLineFileOffset += _lastLineLength;
	_lastLineLength = 0;
	
	while (YES) {
		BOOL found = [self readByte:&byte];
		if (found) {
			if (byte == CR || byte == LF) {
				if ([self handleEOL:byte data:data]) {
					// we've recognized an EOL, so let's break out of the loop
					break;
				}
			}
			else {
				[data appendBytes:(void *)&byte length:1];
			}
		}
		else {
			// so, we've reached the end of the file.  If we're tailing, we'll go to sleep for a bit
			// (unless, of course, we've been told to stop tailing).
			if (self.shouldTail) {
				if (self.shouldStopTailing)
					break;
				else {
					if (self.shouldFollowRename) {
						if ([self isRenamed]) {
							// if the file was renamed half-way through a line then there
							// will be data that hasn't yet been returned.  If that is the
							// case we fall out now, allow that to be returned, and then the
							// next time readLine is called, we'll end up back here, but this
							// time there will be no half-read line.
							if (_lastLineLength != 0)
								break;
							else {
								// open the file, and re-enter the loop through each
								[self openURL:self.fileURL];
								continue;
							}
						}
						else {
							// haven't been renamed yet, so we just wait for more input
							[NSThread sleepForTimeInterval:self.tailFrequency];
						}
					}
					else {
						// don't care if the file has been renamed... just wait for more input
						[NSThread sleepForTimeInterval:self.tailFrequency];
					}
				}
			}
			else {
				// not tailing, so we can return immediately
				break;
			}
		}
	}

	_lastLineNumber++;

	// if we've not been able to read a single byte, we return a nil.  This distinguishes
	// between no data, and an empty line with just a EOL that was stripped
	return _lastLineLength == 0 ? nil : data;
}

/**
 * Takes the data from readLineData and converts it to a string based on the encodings
 */
-(NSString *)readLine {
	NSData *data = [self readLineAsData];
	if (data == nil)
		return nil;
	
	for (int i = 0; i < self.encodings.count; i++) {
		NSStringEncoding encoding = [self.encodings[i] integerValue];
		NSString *string = [[NSString alloc] initWithData:data encoding:encoding];
		if (string != nil)
			return string;
	}
	return nil;
}

/**
 * This is where the end-of-line magic happens.  readLineAsData has already
 * determined that the current byte is either a CR or an LF; now we need to
 * figure out if it actually represents a line-end based on the lineEndIndicator.
 *
 * If is deemed to be a line-end (and sometimes we need to peek at the next byte
 * to do so), the line-end character(s) are appended to the current line's data
 * that is passed in.
 *
 * @return Whether the byte is actually treated as ending the line
 */
-(BOOL)handleEOL:(uint8_t)byte data:(NSMutableData *)currentLineData {
	if (byte == CR && self.lineEndIndicator == BDFileTailerLineEndOnlyCR) {          // Found a CR (matches OnlyCR)
		if (self.shouldStripLineEnds == NO)
			[currentLineData appendBytes:(void *)&byte length:1];
		return YES;
	}
	else if (byte == LF && self.lineEndIndicator == BDFileTailerLineEndOnlyLF) {     // Found a LF (matches OnlyLF)
		if (self.shouldStripLineEnds == NO)
			[currentLineData appendBytes:(void *)&byte length:1];
		return YES;
	}
	else if (self.lineEndIndicator == BDFileTailerLineEndCRLF || self.lineEndIndicator == BDFileTailerLineEndAuto) {
		uint8_t nextByte;
		if ([self peekByte:&nextByte]) {
			if (nextByte == LF) {                                                        // Found a CR+LF (matches CRLF or Auto)
				[self readByte:&nextByte];
				if (self.shouldStripLineEnds == NO) {
					[currentLineData appendBytes:(void *)&byte length:1];
					[currentLineData appendBytes:(void *)&nextByte length:1];
				}
			}
			else {
				if (self.lineEndIndicator == BDFileTailerLineEndAuto) {                // Found a CR (matches Auto)
					if (self.shouldStripLineEnds == NO)
						[currentLineData appendBytes:(void *)&byte length:1];
				}
				else {                                                                     // Found a CR (but doesn't match CRLF)
					// we are looking for CRLF, but only found CR.  In this case,
					// we need to append the CR and indicate we are NOT at line-end
					[currentLineData appendBytes:(void *)&byte length:1];
					return NO;
				}
			}
		}
		else {
			// couldn't peek any more data.  This means we're at end of file
			// so we'll treat that as end of line
			if (self.shouldStripLineEnds == NO)                                          // Found a CR+EOF (matches CRLF or Auto)
				[currentLineData appendBytes:(void *)&byte length:1];
		}
		return YES;
	}
	else {                                                                           // Found CR or LF (with wrong match)
		// note that we only end up here in two circumstances:
		//   1. we read a CR, but the specified line-ending is LF
		//   2. we read a LF, but the specified line-ending is CR
		// in either case, it doesn't count as a line-end match, so
		// we just add it to the data and indicate that it wasn't a EOL
		[currentLineData appendBytes:(void *)&byte length:1];
		return NO;
	}
}

/** 
 * Checks to see whether a file has been renamed out from underneath us.
 */
-(BOOL)isRenamed {
	NSFileHandle *tmp = [NSFileHandle fileHandleForReadingAtPath:[self.fileURL path]];
	BOOL renamed = [self inode:tmp] != [self inode:self.fileHandle];
	[tmp closeFile];
	return renamed;
}

/**
 * Fetches the inode for the passed file handle
 */
-(ino_t)inode:(NSFileHandle *)fileHandle {
	struct stat s;
	fstat([fileHandle fileDescriptor], &s);
	return s.st_ino;
}
@end
